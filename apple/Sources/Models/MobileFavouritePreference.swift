import Foundation

public struct AptevaMobileFavouritePreference: Decodable, Sendable {
    public let value: [String]
    public let revision: Int64

    public var appName: String? { value.first }
}

struct MobileFavouritePatch: Encodable {
    let value: [String]
}
