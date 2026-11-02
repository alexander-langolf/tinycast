import Darwin
import Foundation

@MainActor
final class ForkPolicyMonitor {
    var onChange: (() -> Void)?
    private var sources: [DispatchSourceFileSystemObject] = []
    private var settleTask: Task<Void, Never>?
    private var directory: URL?
    private var files: [String] = []

    isolated deinit {
        settleTask?.cancel()
        for source in sources { source.cancel() }
    }

    func watch(directory: URL, files: [String]) {
        self.directory = directory
        self.files = files
        arm()
    }

    func stop() {
        settleTask?.cancel()
        settleTask = nil
        directory = nil
        for source in sources { source.cancel() }
        sources = []
    }

    private func arm() {
        for source in sources { source.cancel() }
        sources = []
        guard let directory else { return }
        var paths = Set([directory, directory.appending(path: "prompts"), directory.appending(path: "policy"), directory.deletingLastPathComponent()])
        for file in files { paths.insert(directory.appending(path: file)) }
        for path in paths {
            var candidate = path
            var descriptor = Darwin.open(candidate.path, O_EVTONLY)
            while descriptor < 0, candidate.path != "/" {
                candidate.deleteLastPathComponent()
                descriptor = Darwin.open(candidate.path, O_EVTONLY)
            }
            guard descriptor >= 0 else { continue }
            let openedDescriptor = descriptor
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: openedDescriptor, eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.changed() }
            }
            source.setCancelHandler { Darwin.close(openedDescriptor) }
            source.resume()
            sources.append(source)
        }
    }

    private func changed() {
        guard directory != nil else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, directory != nil else { return }
            arm()
            onChange?()
        }
    }
}
