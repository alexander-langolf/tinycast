import Darwin
import Foundation

@MainActor
final class FolderWatcher {
    private var source: (any DispatchSourceFileSystemObject)?
    private var debounce: Task<Void, Never>?
    private var generation = UUID()

    func watch(_ folder: String, changed: @escaping @MainActor () -> Void) {
        stop()
        let descriptor = Darwin.open(folder, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let generation = generation
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename],
            queue: .main)
        // Both handlers inherit this type's main-actor isolation, so the source must deliver on
        // `.main`: a background queue trips Swift 6's executor check and traps the app.
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.debounce?.cancel()
                self.debounce = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    guard let self, self.generation == generation, !Task.isCancelled else { return }
                    changed()
                }
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        generation = UUID()
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
    }

    isolated deinit {
        debounce?.cancel()
        source?.cancel()
    }
}
