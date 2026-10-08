import Foundation

/// A ZDOTDIR that loads the user's own zsh files, then adds the marks an instance reads.
enum TerminalShellShim {
    static let files: [(name: String, contents: String)] = [
        (
            ".zshenv",
            #"""
            _tc_shim=$ZDOTDIR
            ZDOTDIR=$HOME
            [[ -r $HOME/.zshenv ]] && source $HOME/.zshenv
            _tc_user=${ZDOTDIR:-$HOME}
            ZDOTDIR=$_tc_shim

            """#
        ),
        (
            ".zprofile",
            #"""
            ZDOTDIR=$_tc_user
            [[ -r $_tc_user/.zprofile ]] && source $_tc_user/.zprofile
            ZDOTDIR=$_tc_shim

            """#
        ),
        (
            ".zshrc",
            #"""
            ZDOTDIR=$_tc_user
            [[ $HISTFILE == $_tc_shim/* ]] && HISTFILE=$_tc_user/.zsh_history
            [[ -r $_tc_user/.zshrc ]] && source $_tc_user/.zshrc
            ZDOTDIR=$_tc_shim
            setopt no_prompt_sp
            typeset -gi _tc_ran=0
            _tc_precmd() {
              local s=$?
              (( _tc_ran )) && printf '\e]133;D;%s\a' $s
              _tc_ran=0
              local p=${PWD//\%/%25}
              printf '\e]7;file://%s%s\a\e]133;A\a' $HOST ${p// /%20}
            }
            _tc_preexec() { _tc_ran=1; printf '\e]133;C\a' }
            precmd_functions=(_tc_precmd $precmd_functions)
            preexec_functions+=(_tc_preexec)

            """#
        ),
        (
            ".zlogin",
            #"""
            ZDOTDIR=$_tc_user
            [[ -r $_tc_user/.zlogin ]] && source $_tc_user/.zlogin
            unset _tc_shim _tc_user

            """#
        )
    ]

    /// Rewritten on every spawn, so a shim from an older build is never read.
    static func install(in root: URL) -> URL? {
        let name = "\(Bundle.main.bundleIdentifier ?? "tinycast")-zdotdir"
        let directory = root.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in files {
                try file.contents.write(
                    to: directory.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
            }
            return directory
        } catch {
            return nil
        }
    }

    /// kitty's variables would load its own shell integration and duplicate the marks.
    static func environment(base: [String: String], shim: URL) -> [String: String] {
        var environment = base.filter { !$0.key.hasPrefix("KITTY_") && !$0.key.hasPrefix("TERM_PROGRAM") }
        environment["ZDOTDIR"] = shim.path
        environment["TERM"] = "xterm-256color"
        environment["TINYCAST"] = "1"
        environment["TINYCAST_TERMINAL"] = "1"
        // A pager would wait on a keyboard the instance does not forward.
        environment["PAGER"] = "cat"
        environment["GIT_PAGER"] = "cat"
        return environment
    }
}
