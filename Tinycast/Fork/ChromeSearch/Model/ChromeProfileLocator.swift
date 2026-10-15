import Foundation

enum ChromeProfileLocator {
    /// The directory of the profile Chrome last used, or nil when `Local State` doesn't name one.
    static func profileDirectory(
        localState: Data, userDataDirectory: URL, exists: (URL) -> Bool
    ) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: localState) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let name = profile["last_used"] as? String,
            !name.isEmpty, !name.contains("/"), name != "..", name != "."
        else { return nil }
        let directory = userDataDirectory.appending(path: name, directoryHint: .isDirectory)
        return exists(directory) ? directory : nil
    }
}
