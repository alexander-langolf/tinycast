import AppKit
import Carbon
import Darwin
import InputMethodKit
import OSLog

private struct SpikeSample: Encodable, Sendable {
    let timestamp: Date
    let clientBundleID: String?
    let clientAvailable: Bool
    let rectQueryAvailable: Bool
    let rectNonZero: Bool
    let rectUsable: Bool
    let rectWidth: Double?
    let rectHeight: Double?
    let selectedRangeAvailable: Bool
    let lengthAvailable: Bool
    let markedAttributesAvailable: Bool
    let markedAttributeCount: Int?
}

private final class SpikeLog: Sendable {
    private let queue = DispatchQueue(label: "com.tinycast.imk-spike.log", qos: .utility)
    private static let logger = Logger(subsystem: "com.tinycast.imk-spike", category: "metadata")

    func record(_ sample: SpikeSample) {
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                var data = try encoder.encode(sample)
                data.append(10)
                try Self.append(data)
            } catch {
                Self.logger.error("Metadata record could not be written")
            }
        }
    }

    private static func append(_ data: Data) throws {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("com.tinycast.imk-spike", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let folder = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard folder >= 0 else { throw POSIXError(.EACCES) }
        defer { close(folder) }
        var directoryInfo = stat()
        guard fstat(folder, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
              fchmod(folder, 0o700) == 0 else { throw POSIXError(.EACCES) }
        let file = openat(folder, "events.jsonl", O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw POSIXError(.EACCES) }
        defer { close(file) }
        var fileInfo = stat()
        guard fstat(file, &fileInfo) == 0, fileInfo.st_mode & S_IFMT == S_IFREG,
              fileInfo.st_uid == getuid(), fileInfo.st_nlink == 1,
              fchmod(file, 0o600) == 0 else { throw POSIXError(.EACCES) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = write(file, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
    }
}

@objc(TinycastIMKSpikeController)
final class TinycastIMKSpikeController: IMKInputController {
    private static let log = SpikeLog()

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event?.type == .keyDown else { return false }
        let client = sender as? IMKTextInput
        let selection = client?.selectedRange()
        let length = client?.length()
        let attributes = client?.validAttributesForMarkedText()
        var rect = NSRect.zero
        // With no composition, index zero asks the client for the current selection's geometry.
        _ = client?.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        let finite = rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
        let bundle = client?.bundleIdentifier()
        let bundleID = bundle.flatMap { value in
            value.count <= 256 && value.contains(".") && value.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0)
                    || (48...57).contains($0) || $0 == 45 || $0 == 46
            } ? value : nil
        }
        Self.log.record(SpikeSample(
            timestamp: Date(), clientBundleID: bundleID, clientAvailable: client != nil,
            rectQueryAvailable: client != nil, rectNonZero: finite && rect != .zero,
            rectUsable: finite && rect.height > 0,
            rectWidth: rect.width.isFinite ? Double(rect.width) : nil,
            rectHeight: rect.height.isFinite ? Double(rect.height) : nil,
            selectedRangeAvailable: selection.map {
                $0.location != NSNotFound && $0.length != NSNotFound
            } ?? false,
            lengthAvailable: length.map { $0 >= 0 && $0 != NSNotFound } ?? false,
            markedAttributesAvailable: attributes != nil, markedAttributeCount: attributes?.count))
        return false
    }
}

@main
private enum IMKSpike {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let bundleID = Bundle.main.bundleIdentifier,
              let connection = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
              let server = IMKServer(name: connection, bundleIdentifier: bundleID) else { return }
        withExtendedLifetime(server) { app.run() }
    }
}
