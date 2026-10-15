import Foundation
import Observation

/// One open file: its disk snapshot, the page's dirty flag, and the web view showing it.
@MainActor
@Observable
final class MonacoEditorSession {
    var document: MonacoDocument
    private(set) var isDirty = false
    private(set) var isReady = false
    var isSaving = false
    @ObservationIgnored let host = MonacoWebHost()

    init(document: MonacoDocument) {
        self.document = document
    }

    func apply(_ message: MonacoBridgeMessage) {
        switch message {
        case .ready: isReady = true
        case .dirty(let dirty): isDirty = dirty
        case .save, .close: break
        }
    }
}
