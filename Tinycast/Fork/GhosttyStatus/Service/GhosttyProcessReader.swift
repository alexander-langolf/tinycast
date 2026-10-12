import Foundation
import Darwin
import Security

enum GhosttyProcessReader {
    static func startedAt(_ pid: Int32) -> Date? {
        bsdInfo(pid).map {
            Date(
                timeIntervalSince1970: Double($0.pbi_start_tvsec)
                    + Double($0.pbi_start_tvusec) / 1_000_000)
        }
    }

    static func collect(tabs: [GhosttyTabSnapshot]) -> [GhosttyProcessObservation] {
        let terminals = tabs.flatMap(\.terminals)
        let groups = Set(terminals.compactMap(\.foregroundProcessGroup).filter { $0 > 0 })
        var initial: [GhosttyProcessSnapshot] = []
        for group in groups {
            for pid in members(of: group) {
                guard let metadata = snapshot(pid, agent: nil),
                    terminals.contains(where: {
                        $0.foregroundProcessGroup == metadata.group
                            && $0.ttyDevice == metadata.ttyDevice
                    }), metadata.isRunning
                else { continue }
                guard let agent = verifiedAgent(pid) else { continue }
                guard let verified = snapshot(pid, agent: agent),
                    sameProcess(metadata, verified)
                else { continue }
                initial.append(verified)
            }
        }
        return initial.map { .init(initial: $0, rechecked: snapshot($0.id, agent: verifiedAgent($0.id))) }
    }

    static func ttyDevice(_ path: String?) -> UInt32? {
        guard let path, path.hasPrefix("/dev/"), URL(filePath: path).standardized.path == path else {
            return nil
        }
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFCHR else { return nil }
        return UInt32(bitPattern: info.st_rdev)
    }

    private static func sameProcess(_ lhs: GhosttyProcessSnapshot, _ rhs: GhosttyProcessSnapshot) -> Bool {
        lhs.id == rhs.id && lhs.startedAt == rhs.startedAt && lhs.executablePath == rhs.executablePath
            && lhs.group == rhs.group && lhs.foregroundGroup == rhs.foregroundGroup
            && lhs.ttyDevice == rhs.ttyDevice && rhs.isRunning
    }

    private static func snapshot(_ pid: Int32, agent: GhosttyAgentKind?) -> GhosttyProcessSnapshot? {
        guard let info = bsdInfo(pid) else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let executablePath = String(bytes: executable, encoding: .utf8) else { return nil }
        return .init(
            id: pid, group: Int32(bitPattern: info.pbi_pgid),
            foregroundGroup: Int32(bitPattern: info.e_tpgid), ttyDevice: info.e_tdev,
            startedAt: Date(
                timeIntervalSince1970: Double(info.pbi_start_tvsec)
                    + Double(info.pbi_start_tvusec) / 1_000_000),
            executablePath: executablePath, agent: agent,
            isRunning: info.pbi_status != SZOMB && info.pbi_status != 0)
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private static func members(of group: Int32) -> [Int32] {
        let bytes = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(bitPattern: group), nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: min(Int(bytes) / MemoryLayout<Int32>.size + 32, 4096))
        let read = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(bitPattern: group), $0.baseAddress, Int32($0.count))
        }
        guard read > 0 else { return [] }
        return Array(pids.prefix(Int(read) / MemoryLayout<Int32>.size).filter { $0 > 0 })
    }

    private static func verifiedAgent(_ pid: Int32) -> GhosttyAgentKind? {
        var code: SecCode?
        guard
            SecCodeCopyGuestWithAttributes(
                nil, [kSecGuestAttributePid: pid] as CFDictionary,
                SecCSFlags(), &code) == errSecSuccess,
            let code
        else { return nil }
        let requirements: [(GhosttyAgentKind, String)] = [
            (
                .codex,
                "anchor apple generic and identifier \"codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\""
            ),
            (
                .claude,
                "anchor apple generic and identifier \"com.anthropic.claude-code\" and certificate leaf[subject.OU] = \"Q6L2SF6YDW\""
            )
        ]
        for (kind, text) in requirements {
            var requirement: SecRequirement?
            guard
                SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess,
                let requirement
            else { continue }
            if SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement)
                == errSecSuccess
            {
                return kind
            }
        }
        return nil
    }
}
