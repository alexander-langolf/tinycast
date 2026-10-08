import Foundation

/// A ZDOTDIR that loads the user's own zsh files, then adds the marks an instance reads.
enum TerminalShellShim {
    static let files: [(name: String, contents: String)] = [
        (
            ".zshenv",
            #"""
            _tc_shim=$ZDOTDIR
            if (( ${+_TC_ZDOTDIR} )); then
              ZDOTDIR=$_TC_ZDOTDIR
            else
              unset ZDOTDIR
            fi
            unset _TC_ZDOTDIR
            [[ -r ${ZDOTDIR-$HOME}/.zshenv ]] && source ${ZDOTDIR-$HOME}/.zshenv
            _tc_user_set=${+ZDOTDIR}
            _tc_user=${ZDOTDIR-$HOME}
            _tc_restore_zdotdir() {
              if (( _tc_user_set )); then
                ZDOTDIR=$_tc_user
              else
                unset ZDOTDIR
              fi
            }
            ZDOTDIR=$_tc_shim

            """#
        ),
        (
            ".zprofile",
            #"""
            _tc_restore_zdotdir
            [[ -r $_tc_user/.zprofile ]] && source $_tc_user/.zprofile
            ZDOTDIR=$_tc_shim

            """#
        ),
        (
            ".zshrc",
            #"""
            _tc_restore_zdotdir
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
            _tc_restore_zdotdir
            [[ -r $_tc_user/.zlogin ]] && source $_tc_user/.zlogin
            unset _tc_shim _tc_user _tc_user_set
            unfunction _tc_restore_zdotdir

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
        environment["_TC_ZDOTDIR"] = base["ZDOTDIR"]
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
