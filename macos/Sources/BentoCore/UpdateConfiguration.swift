import Foundation

public enum UpdateConfiguration {
    public static let feed = URL(string: "https://raw.githubusercontent.com/AbdullahEgh/Bento-Layout/macos-updates/appcast.xml")!
    public static func validate(feed: URL?, publicKey: String?, developmentBuild: Bool) throws {
        guard !developmentBuild else { throw ConfigurationError.developmentBuild }
        guard let feed, feed.scheme == "https", feed.host == Self.feed.host, feed.path == Self.feed.path,
              feed.user == nil, feed.password == nil, feed.query == nil, feed.fragment == nil else { throw ConfigurationError.feed }
        guard let publicKey, let data = Data(base64Encoded: publicKey), data.count == 32 else { throw ConfigurationError.key }
    }
    public enum ConfigurationError: LocalizedError {
        case developmentBuild, feed, key
        public var errorDescription: String? {
            switch self {
            case .developmentBuild: return "This local preview is not configured for signed OTA releases. Install a signed release to receive updates in Bento."
            case .feed: return "The Mac update feed is not configured correctly."
            case .key: return "The update publisher’s signing key is missing or invalid."
            }
        }
    }
}
