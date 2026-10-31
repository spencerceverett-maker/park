import AppKit
import Darwin

/// Process table, arguments and working directories, via sysctl and libproc.
enum Processes {
    struct Info { let pid: pid_t, ppid: pid_t, pgid: pid_t, tpgid: pid_t, tdev: dev_t, comm: String }

    static func all() -> [Info] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        sysctl(&mib, 4, nil, &size, nil, 0)
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = buffer.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }
        return buffer.prefix(size / MemoryLayout<kinfo_proc>.stride).map { process in
            var comm = process.kp_proc.p_comm
            let name = withUnsafeBytes(of: &comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            return Info(pid: process.kp_proc.p_pid, ppid: process.kp_eproc.e_ppid, pgid: process.kp_eproc.e_pgid,
                        tpgid: process.kp_eproc.e_tpgid, tdev: process.kp_eproc.e_tdev, comm: name)
        }
    }

    /// argv and environment. The environment of Apple platform binaries (like /bin/zsh) isn't readable.
    static func arguments(_ pid: pid_t) -> (args: [String], env: [String: String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return ([], [:]) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return ([], [:]) }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buffer[i] != 0 { i += 1 }   // executable path
        while i < size && buffer[i] == 0 { i += 1 }   // padding
        var strings: [String] = []
        while i < size {
            let start = i
            while i < size && buffer[i] != 0 { i += 1 }
            guard i > start else { break }
            strings.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        var env: [String: String] = [:]
        for pair in strings.dropFirst(argc) {
            if let equals = pair.firstIndex(of: "=") { env[String(pair[..<equals])] = String(pair[pair.index(after: equals)...]) }
        }
        return (Array(strings.prefix(argc)), env)
    }

    static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard size > 0 else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    /// "node /usr/local/bin/claude --resume" → "claude --resume": drop interpreters and shorten paths.
    static func displayCommand(_ args: [String]) -> String {
        var parts = args
        let interpreters: Set<String> = ["node", "python", "python3", "ruby", "bun", "deno"]
        if parts.count > 1, interpreters.contains((parts[0] as NSString).lastPathComponent) { parts.removeFirst() }
        if let first = parts.first { parts[0] = (first as NSString).lastPathComponent }
        return parts.joined(separator: " ")
    }

    /// Total memory footprint of the given processes and all of their descendants.
    static func footprint(ofTreesRootedAt roots: Set<pid_t>) -> UInt64 {
        let processes = all()
        var children: [pid_t: [pid_t]] = [:]
        for process in processes { children[process.ppid, default: []].append(process.pid) }
        var stack = Array(roots)
        var seen = Set<pid_t>()
        var total: UInt64 = 0
        while let pid = stack.popLast() {
            guard seen.insert(pid).inserted else { continue }
            total += MemoryStats.footprint(of: pid)
            stack.append(contentsOf: children[pid] ?? [])
        }
        return total
    }
}

/// Launching apps and waiting until they can take commands.
enum Launcher {
    /// Returns the running app, launching it (in the background) if needed.
    static func ensureRunning(bundleID: String, settle: TimeInterval) -> NSRunningApplication? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated }) {
            return running
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let done = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
            launched = app
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
        guard let app = launched else { return nil }
        let deadline = Date().addingTimeInterval(15)
        while !app.isFinishedLaunching && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        Thread.sleep(forTimeInterval: settle)
        return app
    }
}
