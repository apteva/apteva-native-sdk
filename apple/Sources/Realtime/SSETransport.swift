import Foundation

/// Authenticated, long-lived SSE transport shared by every realtime domain.
///
/// REST requests intentionally retain short resource timeouts. Each SSE
/// subscription owns a delegate-backed URLSession so response bytes are
/// delivered as the network stack receives them. `URLSession.AsyncBytes` can
/// buffer a rapid HTTP/2 event burst until the response goes idle, which makes
/// a native chat appear to jump directly from “Starting” to the final row.
public final class AptevaSSETransport: @unchecked Sendable {
    public static let openEventName = "__apteva_open"

    private let baseURL: URL
    private let bearerToken: String?
    private let protocolClasses: [AnyClass]?

    public init(
        baseURL: URL,
        bearerToken: String?,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.protocolClasses = protocolClasses
    }

    public func events(path: String) -> AsyncThrowingStream<AptevaSSEEvent, Error> {
        let apiBase = baseURL.appendingPathComponent("api", isDirectory: true)
        guard let url = URL(string: path, relativeTo: apiBase)?.absoluteURL else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AptevaAPIError.invalidServerURL)
            }
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60 * 60

        return AsyncThrowingStream { continuation in
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = .shared
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 60 * 60
            configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
            configuration.waitsForConnectivity = true
            configuration.httpMaximumConnectionsPerHost = 6
            if let protocolClasses {
                configuration.protocolClasses = protocolClasses
            }

            let connection = AptevaSSEConnection(
                configuration: configuration,
                request: request,
                continuation: continuation
            )
            continuation.onTermination = { [weak connection] _ in
                connection?.cancel()
            }
            connection.start()
        }
    }

    fileprivate static func connectionMessage(for error: URLError) -> String {
        switch error.code {
        case .cannotFindHost, .cannotConnectToHost:
            "Could not reach this Apteva server. Check its address and port."
        case .timedOut:
            "The Apteva realtime connection timed out."
        case .notConnectedToInternet, .networkConnectionLost:
            "The local network connection is unavailable."
        case .serverCertificateUntrusted, .secureConnectionFailed:
            "The server’s TLS certificate could not be verified."
        default:
            error.localizedDescription
        }
    }
}

private final class AptevaSSEConnection: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let request: URLRequest
    private let continuation: AsyncThrowingStream<AptevaSSEEvent, Error>.Continuation
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var lineBuffer = Data()
    private var eventID: String?
    private var eventName: String?
    private var dataLines: [String] = []
    private var acceptedResponse = false
    private var finished = false
    private let lock = NSLock()

    public init(
        configuration: URLSessionConfiguration,
        request: URLRequest,
        continuation: AsyncThrowingStream<AptevaSSEEvent, Error>.Continuation
    ) {
        self.configuration = configuration
        self.request = request
        self.continuation = continuation
    }

    public func start() {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    public func cancel() {
        lock.lock()
        let shouldFinish = !finished
        finished = true
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        if shouldFinish { continuation.finish() }
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            finish(throwing: AptevaAPIError.invalidResponse)
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            finish(
                throwing: AptevaAPIError.server(
                    status: http.statusCode,
                    message: "Realtime stream returned HTTP \(http.statusCode)."
                )
            )
            completionHandler(.cancel)
            return
        }

        acceptedResponse = true
        continuation.yield(
            AptevaSSEEvent(
                id: nil,
                name: AptevaSSETransport.openEventName,
                data: Data("{}".utf8)
            )
        )
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard acceptedResponse, !isFinished else { return }
        lineBuffer.append(data)
        consumeCompleteLines()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if acceptedResponse, !lineBuffer.isEmpty {
            consumeRemainder()
            emitEvent()
        }
        guard !isFinished else { return }
        if let error = error as? URLError, error.code != .cancelled {
            finish(
                throwing: AptevaAPIError.connection(
                    AptevaSSETransport.connectionMessage(for: error)
                )
            )
        } else if let error {
            finish(throwing: error)
        } else {
            finish()
        }
    }

    private var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func consumeCompleteLines() {
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            var bytes = lineBuffer.prefix(upTo: newline)
            lineBuffer.removeSubrange(...newline)
            if bytes.last == 0x0D { bytes = bytes.dropLast() }
            consume(line: String(decoding: bytes, as: UTF8.self))
        }
    }

    private func consumeRemainder() {
        var bytes = lineBuffer[...]
        lineBuffer.removeAll(keepingCapacity: false)
        if bytes.last == 0x0D { bytes = bytes.dropLast() }
        consume(line: String(decoding: bytes, as: UTF8.self))
    }

    private func consume(line: String) {
        if line.isEmpty {
            emitEvent()
        } else if line.hasPrefix(":") {
            return
        } else if line.hasPrefix("id:") {
            eventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            dataLines.append(value)
        }
    }

    private func emitEvent() {
        guard !dataLines.isEmpty else {
            eventID = nil
            eventName = nil
            return
        }
        continuation.yield(
            AptevaSSEEvent(
                id: eventID,
                name: eventName,
                data: Data(dataLines.joined(separator: "\n").utf8)
            )
        )
        eventID = nil
        eventName = nil
        dataLines.removeAll(keepingCapacity: true)
    }

    private func finish(throwing error: Error? = nil) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
        session?.finishTasksAndInvalidate()
        task = nil
        session = nil
    }
}
