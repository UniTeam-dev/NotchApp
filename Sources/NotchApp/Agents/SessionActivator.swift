import AppKit
import Darwin

/// Переход к сессии по клику.
enum SessionActivator {
    static func activate(_ session: AgentSession) {
        switch session.source {
        case .cursor:
            activateCursor(cwd: session.cwd)
        case .claude:
            activateClaude(session)
        case .cloud:
            break
        }
    }

    private static func activateCursor(cwd: String) {
        guard !cwd.isEmpty else { return }
        if let cursor = Shell.which("cursor") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cursor)
            process.arguments = ["-r", cwd]
            process.environment = Shell.environment()
            try? process.run()
            return
        }
        Shell.open(["-a", "Cursor", cwd])
    }

    /// У Claude Code сессия живёт в терминале. Поднимаемся от pid вверх по дереву
    /// процессов до первого процесса, у которого есть обычное приложение,
    /// и активируем его.
    private static func activateClaude(_ session: AgentSession) {
        guard let pid = session.pid else {
            revealInFinder(session.cwd)
            return
        }

        var current = pid
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy == .regular {
                app.activate(options: [])
                return
            }
            guard let parent = parentPID(of: current), parent > 1 else { break }
            current = parent
        }

        revealInFinder(session.cwd)
    }

    private static func revealInFinder(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = mib.withUnsafeMutableBufferPointer { buffer -> Int32 in
            sysctl(buffer.baseAddress, UInt32(buffer.count), &info, &size, nil, 0)
        }

        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
