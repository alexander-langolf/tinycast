import Foundation

@main
struct FileNavigatorTest {
    static func main() {
        let home = "/Users/test"
        let folders: Set<String> = ["/", home, home + "/github", home + "/github/agentkit"]
        let swift = FileSearchResult(
            url: URL(filePath: home + "/github/agentkit/lib.swift"), isDirectory: false,
            homeDirectory: URL(filePath: home))
        let note = FileSearchResult(
            url: URL(filePath: home + "/notes.txt"), isDirectory: false,
            homeDirectory: URL(filePath: home))
        let folder = FileSearchResult(
            url: URL(filePath: home + "/github/agentkit"), isDirectory: true,
            homeDirectory: URL(filePath: home))
        precondition(
            FileNavigatorPath.destination(for: folder) == (home + "/github/agentkit", nil),
            "a folder opens itself in Show in File Navigator")
        precondition(
            FileNavigatorPath.destination(for: swift) == (home + "/github/agentkit", swift.id),
            "a file opens its parent with the file selected")
        var state = FileNavigatorState(home: home)
        state.setInput("~/github/agentkit/li", home: home, folders: folders)
        precondition(state.folder == home + "/github/agentkit" && state.filter == "li")
        state.setInput("readme", home: home, folders: folders)
        precondition(state.path == .global("readme"))
        state.setInput("~/github/", home: home, folders: folders)
        state.reduce(.tab, rows: [folder], home: home, folders: folders)
        precondition(state.input == "~/github/agentkit/")
        state.reduce(.backspace, rows: [], home: home, folders: folders)
        precondition(state.folder == home + "/github" && state.filter == "agentkit")
        state.setInput("~/github/agentkit/", home: home, folders: folders)
        state.reduce(.pick, rows: [swift], home: home, folders: folders)
        state.setInput("~/", home: home, folders: folders)
        precondition(state.picks == [swift])
        state.reduce(.pick, rows: [note], home: home, folders: folders)
        precondition(state.picks == [swift, note])
        precondition(Set(state.picks.map { FileNavigatorPath.parent($0.id) }).count == 2)
        state.reduce(.enter, rows: [], home: home, folders: folders)
        precondition(state.panel == .actions)
        let targets = state.targets(focused: folder)
        precondition(targets == [swift, note])
        let actions = FileNavigatorAction.actionsFor(targets)
        precondition(actions.first == .edit && actions.contains(.agent) && actions.contains(.copyPath))
        precondition(targets.map(\.id) == [swift.id, note.id])
        state.reduce(.escape, rows: [], home: home, folders: folders)
        state.setInput("~/nope/x", home: home, folders: folders)
        precondition(state.path == .missing(home + "/nope"))
        state.reduce(.shiftTab, rows: [], home: home, folders: folders)
        precondition(state.input == "~/")
        state.reduce(.hidden, rows: [], home: home, folders: folders)
        precondition(state.showHidden)
        precondition(state.preview)
        state.setInput("~/github/ag", home: home, folders: folders)
        state.reduce(.escape, rows: [], home: home, folders: folders)
        precondition(state.input == "~/github/" && !state.picks.isEmpty)
        state.reduce(.escape, rows: [], home: home, folders: folders)
        precondition(state.picks.isEmpty && state.isOpen)
        state.reduce(.escape, rows: [], home: home, folders: folders)
        precondition(!state.isOpen)
        state = FileNavigatorState(home: home)
        state.picks = [swift, folder]
        state.removeVanished([swift.id])
        precondition(state.picks == [folder])
        state.reduce(.selectAll, rows: [folder, swift], home: home, folders: folders)
        precondition(state.picks == [folder, swift])
        state.setInput("~/github/agentkit/", home: home, folders: folders)
        state.reduce(.shiftTab, rows: [], home: home, folders: folders)
        precondition(state.pendingFocus == folder.id)
        state.picks = []
        state.reduce(.enter, rows: [swift], home: home, folders: folders)
        precondition(state.panel == .actions)
        precondition(FileNavigatorAction.actionsFor([folder]).first == .openDefault)
        precondition(FileNavigatorAction.actionsFor([]) == [.ghostty, .ghosttyApp, .searchBelow, .bookmark])
        precondition(FileNavigatorState.ranked([swift, folder], filter: "").first == folder)
        precondition(FileNavigatorState.ranked([swift, folder], filter: "^lib !kit") == [swift])
        precondition(FileNavigatorState.ranked([swift, folder], filter: "!kit") == [swift])
        precondition(FileNavigatorState.ranked([swift], filter: "lib", shouldStop: { true }).isEmpty)
        state.reduce(.escape, rows: [], home: home, folders: folders)
        state.reduce(.subtree, rows: [], home: home, folders: folders)
        precondition(state.subtree)
        state.reduce(.subtree, rows: [], home: home, folders: folders)
        precondition(!state.subtree)
        state.reduce(.togglePreview, rows: [], home: home, folders: folders)
        precondition(!state.preview)
        state.reduce(.bookmarks, rows: [], home: home, folders: folders)
        precondition(state.panel == .bookmarks)
        state.reduce(.escape, rows: [], home: home, folders: folders)
        precondition(state.panel == nil)
        state.setInput("", home: home, folders: folders)
        let emptyPath = state.path
        let emptyFolder = state.folder
        let emptyPicks = state.picks
        state.reduce(.backspace, rows: [], home: home, folders: folders)
        precondition(state.input.isEmpty && state.path == emptyPath && state.folder == emptyFolder)
        precondition(state.picks == emptyPicks && state.panel == nil && state.isOpen)
        precondition(FileNavigatorPath.parseInput("/", home: home, folders: folders) == .folder("/", ""))
        precondition(FileNavigatorPath.parseInput("~", home: home, folders: folders) == .folder(home, ""))
        precondition(FileNavigatorPath.display(home + "work", home: home) == home + "work")
        precondition(FileNavigatorPath.relative(swift.id, to: home + "/github") == "agentkit/lib.swift")
        precondition(
            FileNavigatorPath.relative(home + "/elsewhere/file", to: home + "/github") == "../elsewhere/file")
        precondition(FileNavigatorPath.quote("a'b") == "'a'\\''b'")
        precondition(TerminalEditorKey.controlLetter("z", shift: true) == "y")
        for letter in ["s", "z", "x", "c", "v", "a", "f"] {
            precondition(TerminalEditorKey.controlLetter(letter, shift: false) == letter)
        }
        precondition(TerminalEditorKey.controlLetter("w", shift: false) == nil)
        print("File navigator model passed")
    }
}
