import Foundation

enum ForkClaudeCodeTools {
    static let names = [
        "Read", "Write", "Edit", "Bash", "Grep", "Glob", "AskUserQuestion", "EnterPlanMode",
        "ExitPlanMode", "KillShell", "NotebookEdit", "Skill", "Task", "TaskOutput", "TodoWrite",
        "WebFetch", "WebSearch"
    ]

    static func toClaudeCodeName(_ name: String) -> String {
        names.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    }

    static func fromClaudeCodeName(_ name: String, tools: [AITool]) -> String {
        tools.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name ?? name
    }
}
