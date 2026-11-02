import CryptoKit
import Foundation

struct ForkPolicySnapshot: Sendable {
    @TaskLocal static var current: ForkPolicySnapshot?
    let policy: ForkLyraPolicy
    let prompts: [ForkLyraMode: String]
    let version: String
    let files: [String]

    static func load(directory: URL) throws -> Self {
        let configuration = try read("policy/lyra.json", directory: directory)
        let policy = try ForkLyraPolicy.decode(configuration)
        let files = Array(Set(policy.modes.map(\.prompt))).sorted()
        var bytes: [String: Data] = ["policy/lyra.json": configuration]
        var prompts: [ForkLyraMode: String] = [:]
        for file in files {
            let data = try read(file, directory: directory)
            guard let text = String(data: data, encoding: .utf8),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ForkPolicyFailure(file: URL(filePath: file).lastPathComponent, reason: .invalidPrompt)
            }
            bytes[file] = data
            for mode in policy.modes where mode.prompt == file { prompts[mode.name] = text }
        }
        for (file, data) in bytes {
            guard try read(file, directory: directory) == data else {
                throw ForkPolicyFailure(file: URL(filePath: file).lastPathComponent, reason: .changedDuringRead)
            }
        }
        var hash = SHA256()
        for file in bytes.keys.sorted() {
            let data = bytes[file]!
            hash.update(data: Data("\(file.utf8.count):\(file):\(data.count):".utf8))
            hash.update(data: data)
        }
        let version = hash.finalize().prefix(6).map { String(format: "%02x", $0) }.joined()
        return Self(policy: policy, prompts: prompts, version: version, files: ["policy/lyra.json"] + files)
    }

    private static func read(_ name: String, directory: URL) throws -> Data {
        let file = directory.appending(path: name)
        let resolved = file.resolvingSymlinksInPath().path
        let root = directory.resolvingSymlinksInPath().path + "/"
        guard resolved.hasPrefix(root) else {
            throw ForkPolicyFailure(file: file.lastPathComponent, reason: .invalidValue)
        }
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 262_144 else {
                throw ForkPolicyFailure(file: file.lastPathComponent, reason: .invalidValue)
            }
            return data
        } catch let failure as ForkPolicyFailure { throw failure }
        catch { throw ForkPolicyFailure(file: file.lastPathComponent, reason: .unreadable) }
    }
}
