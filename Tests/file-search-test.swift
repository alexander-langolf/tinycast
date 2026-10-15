import Foundation
import UniformTypeIdentifiers

@main
struct FileSearchTests {
    nonisolated(unsafe) static var failures = 0
    static let home = URL(fileURLWithPath: "/Users/test")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func result(_ path: String, folder: Bool = false) -> FileSearchResult {
        FileSearchResult(url: home.appending(path: path), isDirectory: folder, homeDirectory: home)
    }

    static func main() {
        queryGrammar()
        recents()
        typeFilter()
        scopePolicy()
        pathPolicy()
        ignoreRules()
        policyResolution()
        resultModel()
        ranking()
        previewKind()

        print(failures == 0 ? "File search tests passed" : "\(failures) file search tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func queryGrammar() {
        let policy = FileSearchPolicy(
            scopes: ["~"], ignorePatterns: [], homeDirectory: home)
        expect(
            FileSearchQuery.terms(in: "  annual\treport  ") == ["annual", "report"],
            "terms split on whitespace")
        expect(
            FSearchQuery.text(words: " \n ", filter: .all, policy: policy) == nil,
            "empty input creates no query")
        expect(
            FSearchQuery.text(words: "annual report", filter: .all, policy: policy)
                == "annual report",
            "typed words pass through untouched; scopes are enforced locally")
        let cleared = FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: home)
        expect(
            FSearchQuery.text(words: "report", filter: .all, policy: cleared) == nil,
            "a cleared scope list searches nothing")
        expect(FileSearchQuery.resultLimit == 200, "the displayed result cap is fixed")
    }

    static func recents() {
        expect(
            FileSearchQuery.recentExpression(stamp: .changed, excluding: ["*.tmp"], filter: .images)
                == "kMDItemFSContentChangeDate > $time.now(-259200)"
                + " && kMDItemContentTypeTree == \"public.image\""
                + " && kMDItemFSName != \"*.tmp\"cd",
            "a recents query is one stamp, narrowed by the filter and the ignore list")
        expect(
            FileSearchQuery.recentExpression(stamp: .used)
                == "kMDItemLastUsedDate > $time.now(-2592000)",
            "an unfiltered recents query is the one date clause alone")
        expect(
            FileSearchQuery.RecentStamp.allCases.map(\.rawValue)
                == ["kMDItemFSContentChangeDate", "kMDItemLastUsedDate"],
            "both stamps are asked about: macOS records a last-used date for very few opens")
        expect(
            FileSearchQuery.RecentStamp.changed.window != FileSearchQuery.RecentStamp.used.window,
            "editing is constant, so the changed window is not the used one")
        expect(FileSearchQuery.recentLimit == 20, "the blank screen's row count is fixed")
    }

    static func typeFilter() {
        let policy = FileSearchPolicy(
            scopes: ["~", "/Volumes/Data"], ignorePatterns: [], homeDirectory: home)
        expect(
            FSearchQuery.text(words: "report", filter: .images, policy: policy) == "report type:image",
            "a typed filter becomes fsearch's type word")
        expect(
            FSearchQuery.text(words: "report", filter: .folders, policy: policy) == "report",
            "Folders has no fsearch type, so it is answered from the hit's kind")
        expect(
            FileSearchFilter.folders.admits(isDirectory: true)
                && !FileSearchFilter.folders.admits(isDirectory: false)
                && FileSearchFilter.documents.admits(isDirectory: false)
                && !FileSearchFilter.documents.admits(isDirectory: true)
                && FileSearchFilter.all.admits(isDirectory: true),
            "folders keep directories; typed filters keep files")
        expect(
            FileSearchFilter.documents.spotlightClause?.hasPrefix("(") == true,
            "a filter naming several types parenthesizes them, so the OR cannot leak")
        expect(FileSearchFilter.all.spotlightClause == nil, "All Types constrains nothing")

        expect(
            FileSearchFilter.all.accepts(contentType: nil, isDirectory: false),
            "All Types admits a file whose type never resolved")
        expect(
            FileSearchFilter.folders.accepts(contentType: .folder, isDirectory: true)
                && FileSearchFilter.folders.accepts(contentType: nil, isDirectory: true),
            "Folders admits a directory whether or not its type resolved")
        expect(
            !FileSearchFilter.folders.accepts(contentType: .png, isDirectory: false),
            "Folders rejects a file")
        expect(
            FileSearchFilter.images.accepts(contentType: .png, isDirectory: false)
                && !FileSearchFilter.images.accepts(contentType: .mp3, isDirectory: false),
            "a type filter admits what conforms to it and nothing else")
        expect(
            FileSearchFilter.documents.accepts(contentType: .swiftSource, isDirectory: false),
            "source files conform to public.text, so Documents keeps them")
        expect(
            !FileSearchFilter.images.accepts(contentType: nil, isDirectory: false),
            "an unresolved type is a folder or nothing, never a guessed image")
    }

    static func scopePolicy() {
        func candidate(
            _ name: String, directory: Bool, hidden: Bool = false, package: Bool = false,
            type: UTType? = nil
        ) -> FileSearchScope.Candidate {
            FileSearchScope.Candidate(
                url: home.appending(path: name), isDirectory: directory, isHidden: hidden,
                isPackage: package, contentType: type)
        }
        let selection = FileSearchScope.select([
            candidate("Documents", directory: true),
            candidate("Developer", directory: true),
            candidate("Library", directory: true),
            candidate(".cache", directory: true, hidden: true),
            candidate("Project.xcodeproj", directory: true, package: true),
            candidate("Local.app", directory: true, package: true, type: .application),
            candidate("Notes.txt", directory: false)
        ])
        expect(
            selection.directories.map(\.lastPathComponent) == ["Documents", "Developer"],
            "only visible non-package directories become recursive Spotlight scopes")
        expect(
            selection.rootItems.map(\.url.lastPathComponent)
                == ["Documents", "Developer", "Project.xcodeproj", "Notes.txt"],
            "visible root folders, files and document packages remain direct candidates")
    }

    static func pathPolicy() {
        let shipped = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults)
        for directory in FileSearchIgnoreList.defaults {
            expect(
                FileSearchQuery.isExcludedPath(
                    "/Users/test/Documents/App/\(directory)/file.txt", ignoring: shipped),
                "\(directory) descendants are excluded")
        }
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/App/.git/config", ignoring: shipped),
            "hidden ancestor paths are excluded")
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/Applications/Example.app/Contents/Info.plist", ignoring: shipped),
            "application-bundle contents are excluded")
        expect(
            !FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/Building Plans/target-notes.txt", ignoring: shipped),
            "partial directory-name matches remain searchable")
        expect(
            !FileSearchQuery.isExcludedPath("/Users/test/Documents/Pods.txt", ignoring: shipped),
            "an excluded directory spelling is still valid as a filename")
        expect(
            !FileSearchQuery.isExcludedPath(
                "/Users/test/Documents/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "an empty list still leaves the structural rules in place")
        expect(
            FileSearchQuery.isExcludedPath(
                "/Users/test/.hidden/Notes.txt", ignoring: FileSearchIgnoreList(patterns: [])),
            "hidden paths are structural, not a pattern the user can drop")
    }

    static func ignoreRules() {
        let list = FileSearchIgnoreList(patterns: [
            "*.tmp", "**/[Cc]ache/**", "**/build-output/**", "Archive", "  ", "with\0nul"
        ])
        expect(list.excludes(path: "/Users/test/Documents/notes.TMP"), "a name glob folds case")
        expect(
            list.excludes(path: "/Users/test/Documents/scratch.tmp/keep.txt"),
            "a name glob matches at any depth, not only the last component")
        expect(
            list.excludes(path: "/Users/test/Developer/Cache/blob"),
            "a path glob matches a bracketed alternative")
        expect(
            list.excludes(path: "/Users/test/Developer/cache/blob"),
            "a path glob folds case too")
        expect(
            list.excludes(path: "/Users/test/Developer/app/build-output/index.js"),
            "a path glob matches an interior segment")
        expect(list.excludes(path: "/Users/test/archive/old.txt"), "a literal name folds case")
        expect(
            !list.excludes(path: "/Users/test/Documents/tmp-notes.txt"),
            "a name glob is anchored to the whole component, not a substring")
        expect(
            !list.excludes(path: "/Users/test/Documents/Archived/old.txt"),
            "a literal name never matches a longer component")
        expect(
            !FileSearchIgnoreList(patterns: []).excludes(path: "/Users/test/Documents/node_modules/a"),
            "the shipped rules are supplied by the policy, not baked into the matcher")

        expect(
            list.spotlightNameExclusions == ["*.tmp"],
            "only bare `*` name globs are pushed into the Spotlight expression")
        expect(
            FileSearchIgnoreList(patterns: ["?.log", "a[bc].txt", "say\"hi\"", "back\\slash"])
                .spotlightNameExclusions.isEmpty,
            "Spotlight reads `?`, brackets and quotes literally, so those stay local")
    }

    static func policyResolution() {
        let policy = FileSearchPolicy(
            scopes: ["~", "~/Developer", "/Volumes/Work", "~/Developer"],
            ignorePatterns: ["*.log"], homeDirectory: home)
        expect(policy.includesHome, "a configured home root is held apart for expansion")
        expect(
            policy.directRoots.map(\.path) == ["/Users/test/Developer", "/Volumes/Work"],
            "every other root passes through verbatim, deduplicated in order")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/run.log"),
            "a user pattern applies outside home as well")
        expect(
            policy.ignore.excludes(path: "/Volumes/Work/node_modules/a.js"),
            "the shipped rules always apply on top of the user's")

        let away = FileSearchPolicy(
            scopes: ["~/Developer"], ignorePatterns: [], homeDirectory: home)
        expect(!away.includesHome, "dropping home drops the expansion with it")
        expect(
            FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: home).directRoots.isEmpty,
            "a cleared list resolves to no roots at all")
        expect(
            FileSearchScope.normalize(
                ["/Users/test/Developer", "~/Developer", "/etc"],
                homeDirectory: home) == ["~/Developer", "/etc"],
            "normalizing abbreviates home and drops the duplicate it creates")
        expect(
            FileSearchScope.expand("~", homeDirectory: home).path == "/Users/test",
            "a bare tilde expands to home itself")
    }

    static func resultModel() {
        let nested = result("Documents/Annual Report.pdf")
        expect(nested.id == "/Users/test/Documents/Annual Report.pdf", "identity is the full path")
        expect(nested.name == "Annual Report.pdf", "the full filename keeps its extension")
        expect(nested.parentPath == "~/Documents", "the parent path abbreviates home")
        expect(result("Notes.txt").parentPath == "~", "a home-root item has a bare tilde parent")
        expect(
            nested.parentName == "Documents" && result("Notes.txt").parentName == "test",
            "the parent's own name is what a folder row prefixes itself with")
    }

    static func ranking() {
        let policy = FileSearchPolicy(scopes: ["~"], ignorePatterns: ["*.tmp"], homeDirectory: home)
        let root = home.standardizedFileURL.path
        func hit(_ path: String, dir: Bool = false) -> FSearchHit {
            FSearchHit(path: root + "/" + path, isDirectory: dir)
        }
        let hits = [
            hit("Archive/b.txt"), hit(".config/x.txt"), hit("Apps/Tool.app"), hit("Apps/Tool.app/readme.txt"),
            hit("proj/node_modules/a.txt"), hit("Archive/skip.tmp"), hit("Library/Caches/c.txt"),
            hit("Library/CloudStorage/Drive/d.txt"), hit(".git/config"), hit("Archive/a.txt"),
            FSearchHit(path: "/opt/outside.txt", isDirectory: false), hit("Archive/Folder", dir: true)
        ]
        let rows = FSearchQuery.rows(from: hits, requested: 400, policy: policy, filter: .all)
        expect(
            rows.results.map(\.name) == ["b.txt", "d.txt", "a.txt", "Folder"],
            "fsearch order is kept; hidden, bundles, ignored, Library and out-of-scope rows drop: \(rows.results.map(\.name))"
        )
        let hidden = FileSearchPolicy(
            scopes: ["~"], ignorePatterns: [], homeDirectory: home, showsHidden: true)
        let shown = FSearchQuery.rows(
            from: [hit(".config/x.txt"), hit(".git/config"), hit(".Trash/t.txt")], requested: 400,
            policy: hidden, filter: .all)
        expect(
            shown.results.map(\.name) == ["x.txt"], "hidden search keeps dotfiles but never .git or .Trash")
        let folders = FSearchQuery.rows(from: hits, requested: 400, policy: policy, filter: .folders)
        expect(folders.results.map(\.name) == ["Folder"], "the Folders filter keeps only directories")

        let capped = (0..<205).map { hit("Archive/Report \($0).txt") }
        let full = FSearchQuery.rows(from: capped, requested: 400, policy: policy, filter: .all)
        expect(full.results.count == 200 && !full.mayHaveMore, "rows are capped at 200")
        let short = FSearchQuery.rows(
            from: Array(repeating: hit("proj/node_modules/z.txt"), count: 10), requested: 10,
            policy: policy, filter: .all)
        expect(short.results.isEmpty && short.mayHaveMore, "a full page filtered short asks for more")
        let exhausted = FSearchQuery.rows(
            from: [hit("proj/node_modules/z.txt")], requested: 400, policy: policy, filter: .all)
        expect(!exhausted.mayHaveMore, "a partial page has nothing more to ask for")

        let direct = FileSearchPolicy(
            scopes: ["~/Library/Foo"], ignorePatterns: [], homeDirectory: home)
        expect(
            direct.admits(path: root + "/Library/Foo/a.txt")
                && !direct.admits(path: root + "/Documents/a.txt"),
            "a Library folder the user named is admitted")
        let found = FSearchLocator.locate(
            home: home, path: "/nope:/usr/local/bin", isExecutable: { $0 == "/usr/local/bin/fsearch" })
        expect(found?.path == "/usr/local/bin/fsearch", "PATH is searched when the install dir is empty")
        let installed = FSearchLocator.locate(
            home: home, path: "/usr/local/bin", isExecutable: { _ in true })
        expect(installed?.path == home.appending(path: ".local/bin/fsearch").path, "the install dir wins")
        expect(
            FSearchLocator.locate(home: home, path: "", isExecutable: { _ in false }) == nil,
            "none found is nil")
    }

    static func previewKind() {
        expect(FileSearchPreviewKind(pathExtension: "swift") == .quickLook, "declared text")
        expect(FileSearchPreviewKind(pathExtension: "pdf") == .pdf, "a PDF draws in process")
        expect(FileSearchPreviewKind(pathExtension: "mov") == .media, "a movie plays")
        expect(FileSearchPreviewKind(pathExtension: "jsx") == nil, "undeclared waits on bytes")
        expect(FileSearchPreviewKind(pathExtension: "ts") == nil, ".ts: TypeScript or MPEG-TS")

        let source = Data("export const x = () => <div>é</div>\n".utf8)
        expect(
            FileSearchPreviewKind(pathExtension: "ts", head: source, isWholeFile: true) == .text,
            "TypeScript source is text")
        expect(
            FileSearchPreviewKind(
                pathExtension: "ts", head: Data([0x47, 0x40, 0x00, 0x10]), isWholeFile: false)
                == .media,
            "an MPEG-TS stream still plays")
        expect(
            FileSearchPreviewKind(pathExtension: "jsx", head: Data([0xFF, 0x00]), isWholeFile: true)
                == .quickLook,
            "undeclared binary falls back to QuickLook")

        let cut = Data("café".utf8).dropLast()
        expect(FileSearchPreviewKind.isText(cut, isWholeFile: false), "a read may cut a character")
        expect(!FileSearchPreviewKind.isText(cut, isWholeFile: true), "a whole file must be UTF-8")
        expect(
            !FileSearchPreviewKind.isText(Data("abc".utf8) + [0xFF], isWholeFile: false),
            "a read forgives a cut character, not a malformed byte")
    }
}
