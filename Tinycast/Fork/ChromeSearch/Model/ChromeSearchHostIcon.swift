import Foundation

enum ChromeSearchHostIcon {
    private static let brands: [String: String] = ["github.com": "BrandGitHub"]

    /// The asset for a URL's host or any of its subdomains, nil for a host without a brand mark.
    static func asset(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        for (domain, asset) in brands where host == domain || host.hasSuffix("." + domain) {
            return asset
        }
        return nil
    }
}
