import Foundation
import Observation

@MainActor
@Observable
final class ForkPolicyStore {
    private(set) static weak var current: ForkPolicyStore?
    private(set) var snapshot: ForkPolicySnapshot?
    var directory: String {
        didSet {
            defaults.set(directory, forKey: "fork.policy.directory")
            if running { scheduleReload() }
        }
    }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fallbackDirectory: URL?
    @ObservationIgnored private let monitor = ForkPolicyMonitor()
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var running = false

    init(defaults: UserDefaults = .standard, fallbackDirectory: URL? = Bundle.main.resourceURL) {
        self.defaults = defaults
        self.fallbackDirectory = fallbackDirectory
        directory = defaults.string(forKey: "fork.policy.directory") ?? "~/github/tinycast/server"
    }

    isolated deinit { reloadTask?.cancel() }

    func start() {
        guard !running else { return }
        Self.current = self
        running = true
        monitor.onChange = { [weak self] in self?.scheduleReload() }
        scheduleReload()
    }

    func stop() {
        running = false
        generation += 1
        reloadTask?.cancel()
        reloadTask = nil
        monitor.stop()
        monitor.onChange = nil
        if Self.current === self { Self.current = nil }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in await self?.reload() }
    }

    func reload() async {
        generation += 1
        let version = generation
        let folder = URL(filePath: (directory as NSString).expandingTildeInPath)
        if running { monitor.watch(directory: folder, files: snapshot?.files ?? ["policy/lyra.json"]) }
        let result = await Self.load(directory: folder, fallbackDirectory: fallbackDirectory)
        guard !Task.isCancelled, generation == version else { return }
        switch result {
        case .success(let candidate): accept(candidate, directory: folder)
        case .failure(let failure):
            reject(failure)
            if snapshot == nil, let fallbackDirectory {
                let fallback = await Self.load(directory: fallbackDirectory, fallbackDirectory: nil)
                guard !Task.isCancelled, generation == version else { return }
                if case .success(let candidate) = fallback { accept(candidate, directory: folder) }
            }
        }
    }

    private func accept(_ candidate: ForkPolicySnapshot, directory: URL) {
        if running { monitor.watch(directory: directory, files: candidate.files) }
        guard candidate.version != snapshot?.version else { return }
        snapshot = candidate
        ForkTrace.begin(.lyra, category: .lyra, step: .policyReload)
            .end(.success, fields: .init(policyVersion: candidate.version))
        onChange?()
    }

    private func reject(_ failure: ForkPolicyFailure) {
        ForkTrace.begin(.lyra, category: .lyra, step: .policyReload).end(
            .failed, fields: .init(policyVersion: snapshot?.version, policyFile: failure.file, policyFailure: failure.reason))
    }

    @concurrent
    private static func load(directory: URL, fallbackDirectory: URL?) async -> Result<ForkPolicySnapshot, ForkPolicyFailure> {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
        let source = !exists ? fallbackDirectory ?? directory : directory
        do { return .success(try ForkPolicySnapshot.load(directory: source)) }
        catch let error as ForkPolicyFailure { return .failure(error) }
        catch { return .failure(ForkPolicyFailure(file: "lyra.json", reason: .unreadable)) }
    }
}
