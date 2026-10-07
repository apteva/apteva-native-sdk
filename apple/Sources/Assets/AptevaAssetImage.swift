#if canImport(UIKit)
import AptevaNativeSDK
import Foundation
import SwiftUI
import UIKit

enum AptevaAssetImagePayload {
    case raster(UIImage)
    case svg(UIImage)

    init?(data: Data) {
        if let image = UIImage(data: data) {
            self = .raster(image)
            return
        }

        guard let markup = String(data: data, encoding: .utf8),
              markup.range(of: "<svg", options: [.caseInsensitive]) != nil,
              let image = AptevaNativeSVGRenderer.image(data: data) else {
            return nil
        }
        self = .svg(image)
    }

    var image: UIImage {
        switch self {
        case let .raster(image), let .svg(image): image
        }
    }
}

@MainActor
private final class AptevaAssetImageCache {
    static let shared = AptevaAssetImageCache()

    private let images = NSCache<NSString, UIImage>()

    func image(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        images.setObject(image, forKey: key as NSString)
    }
}

private enum AptevaNativeSVGRenderer {
    private static let outputSize = CGSize(width: 64, height: 64)
    private static let currentColor = UIColor(red: 249 / 255, green: 115 / 255, blue: 22 / 255, alpha: 1)

    static func image(data: Data) -> UIImage? {
        let parserDelegate = SVGDocumentParser(currentColor: currentColor)
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse(), let document = parserDelegate.document else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { renderer in
            let context = renderer.cgContext
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            let scale = min(outputSize.width / document.viewBox.width, outputSize.height / document.viewBox.height)
            let x = (outputSize.width - document.viewBox.width * scale) / 2 - document.viewBox.minX * scale
            let y = (outputSize.height - document.viewBox.height * scale) / 2 - document.viewBox.minY * scale
            context.translateBy(x: x, y: y)
            context.scaleBy(x: scale, y: scale)

            for node in document.nodes {
                if let fill = node.fill {
                    context.addPath(node.path)
                    context.setFillColor(fill)
                    context.drawPath(using: node.usesEvenOddFill ? .eoFill : .fill)
                }
                if let stroke = node.stroke, node.strokeWidth > 0 {
                    context.addPath(node.path)
                    context.setStrokeColor(stroke)
                    context.setLineWidth(node.strokeWidth)
                    context.setLineCap(node.lineCap)
                    context.setLineJoin(node.lineJoin)
                    context.strokePath()
                }
            }
        }
    }
}

private struct SVGDocument {
    let viewBox: CGRect
    let nodes: [SVGNode]
}

private struct SVGNode {
    let path: CGPath
    let fill: CGColor?
    let stroke: CGColor?
    let strokeWidth: CGFloat
    let lineCap: CGLineCap
    let lineJoin: CGLineJoin
    let usesEvenOddFill: Bool
}

private final class SVGDocumentParser: NSObject, XMLParserDelegate {
    private let currentColor: UIColor
    private var viewBox: CGRect?
    private var nodes: [SVGNode] = []
    private var rootAttributes: [String: String] = [:]

    var document: SVGDocument? {
        guard let viewBox, viewBox.width > 0, viewBox.height > 0, !nodes.isEmpty else { return nil }
        return SVGDocument(viewBox: viewBox, nodes: nodes)
    }

    init(currentColor: UIColor) {
        self.currentColor = currentColor
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = elementName.lowercased()
        if name == "svg" {
            rootAttributes = attributeDict
            if let values = attributeDict["viewBox"].map(svgNumbers), values.count == 4 {
                viewBox = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            } else if let width = attributeDict["width"].flatMap(svgNumber),
                      let height = attributeDict["height"].flatMap(svgNumber) {
                viewBox = CGRect(x: 0, y: 0, width: width, height: height)
            }
            return
        }

        guard let path = shapePath(name: name, attributes: attributeDict) else { return }
        nodes.append(
            SVGNode(
                path: path,
                fill: color(attributeDict["fill"] ?? rootAttributes["fill"] ?? "black"),
                stroke: color(attributeDict["stroke"] ?? rootAttributes["stroke"] ?? "none"),
                strokeWidth: attributeDict["stroke-width"].flatMap(svgNumber)
                    ?? rootAttributes["stroke-width"].flatMap(svgNumber)
                    ?? 1,
                lineCap: lineCap(attributeDict["stroke-linecap"] ?? rootAttributes["stroke-linecap"]),
                lineJoin: lineJoin(attributeDict["stroke-linejoin"] ?? rootAttributes["stroke-linejoin"]),
                usesEvenOddFill: (attributeDict["fill-rule"] ?? rootAttributes["fill-rule"]) == "evenodd"
            )
        )
    }

    private func shapePath(name: String, attributes: [String: String]) -> CGPath? {
        switch name {
        case "path":
            return attributes["d"].flatMap(SVGPathParser.path)
        case "rect":
            guard let width = attributes["width"].flatMap(svgNumber),
                  let height = attributes["height"].flatMap(svgNumber) else { return nil }
            let rect = CGRect(
                x: attributes["x"].flatMap(svgNumber) ?? 0,
                y: attributes["y"].flatMap(svgNumber) ?? 0,
                width: width,
                height: height
            )
            let rx = attributes["rx"].flatMap(svgNumber) ?? 0
            let ry = attributes["ry"].flatMap(svgNumber) ?? rx
            return CGPath(roundedRect: rect, cornerWidth: rx, cornerHeight: ry, transform: nil)
        case "circle":
            guard let cx = attributes["cx"].flatMap(svgNumber),
                  let cy = attributes["cy"].flatMap(svgNumber),
                  let radius = attributes["r"].flatMap(svgNumber) else { return nil }
            return CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2), transform: nil)
        case "ellipse":
            guard let cx = attributes["cx"].flatMap(svgNumber),
                  let cy = attributes["cy"].flatMap(svgNumber),
                  let rx = attributes["rx"].flatMap(svgNumber),
                  let ry = attributes["ry"].flatMap(svgNumber) else { return nil }
            return CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
        case "line":
            guard let x1 = attributes["x1"].flatMap(svgNumber),
                  let y1 = attributes["y1"].flatMap(svgNumber),
                  let x2 = attributes["x2"].flatMap(svgNumber),
                  let y2 = attributes["y2"].flatMap(svgNumber) else { return nil }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
            return path
        case "polyline", "polygon":
            let values = attributes["points"].map(svgNumbers) ?? []
            guard values.count >= 4 else { return nil }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: values[0], y: values[1]))
            for index in stride(from: 2, to: values.count - 1, by: 2) {
                path.addLine(to: CGPoint(x: values[index], y: values[index + 1]))
            }
            if name == "polygon" { path.closeSubpath() }
            return path
        default:
            return nil
        }
    }

    private func color(_ value: String) -> CGColor? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "none", "transparent": return nil
        case "currentcolor": return currentColor.cgColor
        case "black": return UIColor.black.cgColor
        case "white": return UIColor.white.cgColor
        default:
            guard normalized.first == "#" else { return currentColor.cgColor }
            let hex = String(normalized.dropFirst())
            guard let value = UInt64(hex, radix: 16) else { return currentColor.cgColor }
            switch hex.count {
            case 3:
                return UIColor(
                    red: CGFloat((value >> 8) & 0xF) / 15,
                    green: CGFloat((value >> 4) & 0xF) / 15,
                    blue: CGFloat(value & 0xF) / 15,
                    alpha: 1
                ).cgColor
            case 6:
                return UIColor(
                    red: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255,
                    alpha: 1
                ).cgColor
            default:
                return currentColor.cgColor
            }
        }
    }

    private func lineCap(_ value: String?) -> CGLineCap {
        switch value?.lowercased() {
        case "round": return .round
        case "square": return .square
        default: return .butt
        }
    }

    private func lineJoin(_ value: String?) -> CGLineJoin {
        switch value?.lowercased() {
        case "round": return .round
        case "bevel": return .bevel
        default: return .miter
        }
    }
}

private enum SVGPathToken {
    case command(Character)
    case number(CGFloat)
}

private enum SVGPathParser {
    static func path(_ source: String) -> CGPath? {
        let tokens = tokenize(source)
        guard !tokens.isEmpty else { return nil }

        let path = CGMutablePath()
        var index = 0
        var command: Character?
        var previousCommand: Character?
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var cubicControl: CGPoint?
        var quadraticControl: CGPoint?

        func number(_ offset: Int = 0) -> CGFloat? {
            guard index + offset < tokens.count,
                  case let .number(value) = tokens[index + offset] else { return nil }
            return value
        }

        func point(_ x: CGFloat, _ y: CGFloat, relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if case let .command(value) = tokens[index] {
                command = value
                index += 1
                if value == "Z" || value == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    previousCommand = value
                    cubicControl = nil
                    quadraticControl = nil
                    continue
                }
            }

            guard let activeCommand = command else { return nil }
            let relative = activeCommand.isLowercase
            let normalized = Character(activeCommand.uppercased())

            switch normalized {
            case "M":
                guard let x = number(), let y = number(1) else { return nil }
                index += 2
                current = point(x, y, relative: relative)
                path.move(to: current)
                subpathStart = current
                command = relative ? "l" : "L"
                cubicControl = nil
                quadraticControl = nil
            case "L":
                guard let x = number(), let y = number(1) else { return nil }
                index += 2
                current = point(x, y, relative: relative)
                path.addLine(to: current)
                cubicControl = nil
                quadraticControl = nil
            case "H":
                guard let x = number() else { return nil }
                index += 1
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
                cubicControl = nil
                quadraticControl = nil
            case "V":
                guard let y = number() else { return nil }
                index += 1
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
                cubicControl = nil
                quadraticControl = nil
            case "C":
                guard let x1 = number(), let y1 = number(1), let x2 = number(2), let y2 = number(3),
                      let x = number(4), let y = number(5) else { return nil }
                index += 6
                let control1 = point(x1, y1, relative: relative)
                let control2 = point(x2, y2, relative: relative)
                let destination = point(x, y, relative: relative)
                path.addCurve(to: destination, control1: control1, control2: control2)
                current = destination
                cubicControl = control2
                quadraticControl = nil
            case "S":
                guard let x2 = number(), let y2 = number(1), let x = number(2), let y = number(3) else { return nil }
                index += 4
                let control1: CGPoint
                if let cubicControl, previousCommand.map({ "CS".contains($0.uppercased()) }) == true {
                    control1 = CGPoint(x: current.x * 2 - cubicControl.x, y: current.y * 2 - cubicControl.y)
                } else {
                    control1 = current
                }
                let control2 = point(x2, y2, relative: relative)
                let destination = point(x, y, relative: relative)
                path.addCurve(to: destination, control1: control1, control2: control2)
                current = destination
                cubicControl = control2
                quadraticControl = nil
            case "Q":
                guard let x1 = number(), let y1 = number(1), let x = number(2), let y = number(3) else { return nil }
                index += 4
                let control = point(x1, y1, relative: relative)
                let destination = point(x, y, relative: relative)
                path.addQuadCurve(to: destination, control: control)
                current = destination
                quadraticControl = control
                cubicControl = nil
            case "T":
                guard let x = number(), let y = number(1) else { return nil }
                index += 2
                let control: CGPoint
                if let quadraticControl, previousCommand.map({ "QT".contains($0.uppercased()) }) == true {
                    control = CGPoint(x: current.x * 2 - quadraticControl.x, y: current.y * 2 - quadraticControl.y)
                } else {
                    control = current
                }
                let destination = point(x, y, relative: relative)
                path.addQuadCurve(to: destination, control: control)
                current = destination
                quadraticControl = control
                cubicControl = nil
            case "A":
                guard let rx = number(), let ry = number(1), let rotation = number(2),
                      let largeArc = number(3), let sweep = number(4),
                      let x = number(5), let y = number(6) else { return nil }
                index += 7
                let destination = point(x, y, relative: relative)
                addArc(
                    to: path,
                    from: current,
                    to: destination,
                    rx: rx,
                    ry: ry,
                    rotation: rotation,
                    largeArc: largeArc != 0,
                    sweep: sweep != 0
                )
                current = destination
                cubicControl = nil
                quadraticControl = nil
            default:
                return nil
            }
            previousCommand = activeCommand
        }
        return path
    }

    private static func tokenize(_ source: String) -> [SVGPathToken] {
        let pattern = #"[AaCcHhLlMmQqSsTtVvZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: source) else { return nil }
            let token = String(source[swiftRange])
            if token.count == 1, let character = token.first, character.isLetter {
                return .command(character)
            }
            guard let value = Double(token) else { return nil }
            return .number(CGFloat(value))
        }
    }

    private static func addArc(
        to path: CGMutablePath,
        from start: CGPoint,
        to end: CGPoint,
        rx inputRX: CGFloat,
        ry inputRY: CGFloat,
        rotation: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        var rx = abs(inputRX)
        var ry = abs(inputRY)
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let xPrime = cosPhi * dx + sinPhi * dy
        let yPrime = -sinPhi * dx + cosPhi * dy

        let radiusScale = (xPrime * xPrime) / (rx * rx) + (yPrime * yPrime) / (ry * ry)
        if radiusScale > 1 {
            let adjustment = sqrt(radiusScale)
            rx *= adjustment
            ry *= adjustment
        }

        let numerator = max(0, rx * rx * ry * ry - rx * rx * yPrime * yPrime - ry * ry * xPrime * xPrime)
        let denominator = rx * rx * yPrime * yPrime + ry * ry * xPrime * xPrime
        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let factor = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let centerPrimeX = factor * (rx * yPrime / ry)
        let centerPrimeY = factor * (-ry * xPrime / rx)
        let center = CGPoint(
            x: cosPhi * centerPrimeX - sinPhi * centerPrimeY + (start.x + end.x) / 2,
            y: sinPhi * centerPrimeX + cosPhi * centerPrimeY + (start.y + end.y) / 2
        )

        let ux = (xPrime - centerPrimeX) / rx
        let uy = (yPrime - centerPrimeY) / ry
        let vx = (-xPrime - centerPrimeX) / rx
        let vy = (-yPrime - centerPrimeY) / ry
        let startAngle = atan2(uy, ux)
        var deltaAngle = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !sweep, deltaAngle > 0 { deltaAngle -= 2 * .pi }
        if sweep, deltaAngle < 0 { deltaAngle += 2 * .pi }

        let steps = max(2, Int(ceil(abs(deltaAngle) / (.pi / 16))))
        for step in 1...steps {
            let angle = startAngle + deltaAngle * CGFloat(step) / CGFloat(steps)
            let cosAngle = cos(angle)
            let sinAngle = sin(angle)
            path.addLine(
                to: CGPoint(
                    x: center.x + cosPhi * rx * cosAngle - sinPhi * ry * sinAngle,
                    y: center.y + sinPhi * rx * cosAngle + cosPhi * ry * sinAngle
                )
            )
        }
    }
}

private func svgNumber(_ source: String) -> CGFloat? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let numeric = trimmed.replacingOccurrences(of: "px", with: "")
    guard let value = Double(numeric) else { return nil }
    return CGFloat(value)
}

private func svgNumbers(_ source: String) -> [CGFloat] {
    let pattern = #"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return expression.matches(in: source, range: range).compactMap { match in
        guard let swiftRange = Range(match.range, in: source),
              let value = Double(source[swiftRange]) else { return nil }
        return CGFloat(value)
    }
}

/// Displays an authenticated same-origin image asset while keeping bearer
/// credentials out of third-party requests. Raster assets are decoded by
/// UIKit. SVG assets fall back to the caller's native SF Symbol; this component
/// deliberately never embeds web content in an otherwise-native surface.
public struct AptevaAuthenticatedAssetImage: View {
    let reference: String
    let client: AptevaAPIClient
    var fallbackSystemName = "shippingbox.fill"

    @State private var payload: AptevaAssetImagePayload?
    @State private var isLoading = false
    @State private var failed = false

    private var normalizedReference: String {
        reference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        Group {
            if let payload {
                switch payload {
                case let .raster(image), let .svg(image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    fallbackImage
                }
            }
        }
        .task(id: taskIdentity) { await load() }
    }

    @MainActor
    private func load() async {
        payload = nil
        failed = false
        guard !normalizedReference.isEmpty else { return }

        if let image = AptevaAssetImageCache.shared.image(for: taskIdentity) {
            payload = .raster(image)
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await client.assetData(reference: normalizedReference)
            guard let decoded = AptevaAssetImagePayload(data: data) else {
                failed = true
                return
            }
            payload = decoded
            AptevaAssetImageCache.shared.insert(decoded.image, for: taskIdentity)
        } catch {
            failed = true
        }
    }

    public init(
        reference: String,
        client: AptevaAPIClient,
        fallbackSystemName: String = "shippingbox.fill"
    ) {
        self.reference = reference
        self.client = client
        self.fallbackSystemName = fallbackSystemName
    }

    var taskIdentity: String {
        "\(client.baseURL.absoluteString)|\(normalizedReference)"
    }

    private var fallbackImage: some View {
        Image(systemName: fallbackSystemName)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.monochrome)
            .opacity(failed || normalizedReference.isEmpty ? 0.72 : 1)
    }
}
#endif
