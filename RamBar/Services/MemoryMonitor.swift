import Foundation
import AppKit
import Combine

class MemoryMonitor: ObservableObject {
    @Published var systemMemory: SystemMemory = .zero
    @Published var processes: [ProcessMemory] = []

    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var currentPressure: MemoryPressure = .normal
    private let hostPort = mach_host_self()

    /// Cached bundle IDs by binary path — paths don't change their bundle IDs at runtime.
    private var bundleIDCache: [String: String?] = [:]

    deinit {
        stop()
    }

    var refreshInterval: TimeInterval = 3.0 {
        didSet {
            guard oldValue != refreshInterval else { return }
            restart()
        }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        setupPressureMonitoring()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    private func restart() {
        stop()
        start()
    }

    func refresh() {
        systemMemory = fetchSystemMemory()
        processes = fetchProcesses()
    }

    // MARK: - System Memory

    private func fetchSystemMemory() -> SystemMemory {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(self.hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return .zero }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory

        let freePages = UInt64(stats.free_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let external = UInt64(stats.external_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let cached = external + purgeable
        let available = freePages + speculative + cached
        let used = total > available ? total - available : 0
        let free = total - used

        let pressure: MemoryPressure
        if currentPressure == .critical {
            pressure = .critical
        } else if currentPressure == .warning {
            pressure = .warning
        } else {
            let pct = total > 0 ? Int((Double(used) / Double(total)) * 100) : 0
            if pct > 90 { pressure = .critical }
            else if pct > 75 { pressure = .warning }
            else { pressure = .normal }
        }

        return SystemMemory(total: total, used: used, free: free, pressure: pressure)
    }

    // MARK: - Memory Pressure

    private func setupPressureMonitoring() {
        pressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .main
        )
        pressureSource?.setEventHandler { [weak self] in
            guard let self, let source = self.pressureSource else { return }
            let event = source.data
            if event.contains(.critical) {
                self.currentPressure = .critical
            } else if event.contains(.warning) {
                self.currentPressure = .warning
            } else {
                self.currentPressure = .normal
            }
            self.refresh()
        }
        pressureSource?.resume()
    }

    // MARK: - Per-Process Memory

    private struct RawProcess {
        let pid: pid_t
        let memory: UInt64
        let name: String
        let bundleID: String?   // base bundle ID (helper suffixes already stripped)
        let icon: NSImage?
    }

    private func fetchProcesses() -> [ProcessMemory] {
        var pids = [pid_t](repeating: 0, count: 2048)
        let byteCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let pidCount = Int(byteCount) / MemoryLayout<pid_t>.size

        let runningApps = NSWorkspace.shared.runningApplications
        let appMap = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })

        // Map base bundle ID → (display name, icon) for resolving grouped helpers
        let bundleDisplayMap = makeBundleDisplayMap(from: runningApps)

        var rawProcesses: [RawProcess] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            let memory = getPhysicalFootprint(pid: pid)
            guard memory > 10_000_000 else { continue }

            if let app = appMap[pid] {
                // GUI / registered app — NSWorkspace gives us name, icon, bundle ID directly
                let baseID = app.bundleIdentifier.map { stripHelperSuffixes($0) }
                rawProcesses.append(RawProcess(
                    pid: pid, memory: memory,
                    name: app.localizedName ?? "Unknown",
                    bundleID: baseID,
                    icon: app.icon
                ))
            } else {
                // Background process — use proc_pidpath for full name (proc_name caps at 16 chars)
                var pathBuffer = [UInt8](repeating: 0, count: 4096)
                let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
                guard pathLen > 0 else { continue }

                let fullPath = String(bytes: pathBuffer.prefix(Int(pathLen)), encoding: .utf8) ?? ""
                let binaryName = URL(fileURLWithPath: fullPath).deletingPathExtension().lastPathComponent

                // For interpreted runtimes, check pbi_name which libuv/setproctitle updates
                let interpretedRuntimes: Set<String> = ["node", "python", "python3", "ruby",
                                                         "java", "perl", "deno", "bun"]
                let name: String
                if interpretedRuntimes.contains(binaryName.lowercased()),
                   let title = getProcessTitle(pid: pid),
                   !title.hasPrefix("/") {
                    name = title
                } else {
                    name = binaryName.isEmpty ? fallbackProcName(pid) : binaryName
                }

                let bundleID = getBundleID(for: fullPath)
                let icon = NSWorkspace.shared.icon(forFile: fullPath)

                guard !name.isEmpty else { continue }
                rawProcesses.append(RawProcess(
                    pid: pid, memory: memory, name: name,
                    bundleID: bundleID, icon: icon
                ))
            }
        }

        let grouped = groupProcesses(rawProcesses, bundleDisplayMap: bundleDisplayMap)
        return Array(grouped.sorted { $0.memory > $1.memory }.prefix(15))
    }

    // MARK: - Grouping

    private func groupProcesses(
        _ processes: [RawProcess],
        bundleDisplayMap: [String: (name: String, icon: NSImage?)]
    ) -> [ProcessMemory] {
        var groups: [String: (memory: UInt64, name: String, icon: NSImage?, pid: pid_t)] = [:]

        for proc in processes {
            let groupKey: String
            let displayName: String
            var displayIcon: NSImage? = proc.icon

            if let baseID = proc.bundleID {
                groupKey = baseID
                // Prefer the main app's name/icon (e.g., "Google Chrome" not "Google Chrome Helper")
                if let info = bundleDisplayMap[baseID] {
                    displayName = info.name
                    displayIcon = info.icon ?? proc.icon
                } else {
                    displayName = proc.name
                }
            } else {
                // No bundle ID (CLI tools, system daemons) — group by name
                groupKey = proc.name
                displayName = proc.name
            }

            if var existing = groups[groupKey] {
                existing.memory += proc.memory
                groups[groupKey] = existing
            } else {
                groups[groupKey] = (proc.memory, displayName, displayIcon, proc.pid)
            }
        }

        return groups.map { _, info in
            ProcessMemory(id: info.pid, name: info.name, memory: info.memory, icon: info.icon)
        }
    }

    /// Builds a map from base bundle ID → (display name, icon) using NSWorkspace apps.
    /// Prefers the main app entry (bundle ID == base ID) over helper variants.
    private func makeBundleDisplayMap(
        from apps: [NSRunningApplication]
    ) -> [String: (name: String, icon: NSImage?)] {
        var map: [String: (name: String, icon: NSImage?)] = [:]
        for app in apps {
            guard let bid = app.bundleIdentifier, let name = app.localizedName else { continue }
            let baseID = stripHelperSuffixes(bid)
            // Exact match (main app) wins; otherwise first-seen wins
            if map[baseID] == nil || bid == baseID {
                map[baseID] = (name, app.icon)
            }
        }
        return map
    }

    // MARK: - Bundle ID Helpers

    /// Strips helper-process suffixes from a bundle ID to get the base app's bundle ID.
    /// Handles both dot-separated (com.google.Chrome.helper.renderer)
    /// and space-separated (com.microsoft.VSCode Helper (Renderer)) conventions.
    private func stripHelperSuffixes(_ bundleID: String) -> String {
        // Space-separated suffixes (Electron apps, VS Code, Slack, etc.)
        let spaceSuffixes = [
            " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)",
            " Helper (Alerts)", " Helper", " Crashpad Handler"
        ]
        for suffix in spaceSuffixes.sorted(by: { $0.count > $1.count }) {
            if bundleID.hasSuffix(suffix) {
                return String(bundleID.dropLast(suffix.count))
            }
        }

        // Dot-separated suffixes (Chrome, some Electron forks)
        let dotSuffixes = [
            ".helper.renderer", ".helper.gpu", ".helper.alerts",
            ".helper.plugin", ".helper.crashpad", ".helper",
            ".crashpad", ".renderer", ".gpu"
        ]
        let lower = bundleID.lowercased()
        for suffix in dotSuffixes.sorted(by: { $0.count > $1.count }) {
            if lower.hasSuffix(suffix) {
                return String(bundleID.dropLast(suffix.count))
            }
        }

        return bundleID
    }

    /// Finds the bundle ID for a binary by walking up its path to the nearest .app bundle.
    /// Results are cached by path since bundle IDs don't change at runtime.
    private func getBundleID(for path: String) -> String? {
        if let cached = bundleIDCache[path] { return cached }

        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if url.pathExtension == "app" {
                let infoPlist = url.appendingPathComponent("Contents/Info.plist")
                let rawID = NSDictionary(contentsOf: infoPlist)?["CFBundleIdentifier"] as? String
                let baseID = rawID.map { stripHelperSuffixes($0) }
                bundleIDCache[path] = baseID
                return baseID
            }
        }

        bundleIDCache[path] = nil
        return nil
    }

    // MARK: - Memory API

    /// Returns physical footprint matching Activity Monitor's Memory column.
    /// Uses task_vm_info (same API as Activity Monitor) with proc_pid_rusage fallback.
    private func getPhysicalFootprint(pid: pid_t) -> UInt64 {
        var task: mach_port_t = 0
        if task_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS {
            defer { mach_port_deallocate(mach_task_self_, task) }
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS, info.phys_footprint > 0 {
                return info.phys_footprint
            }
        }
        // Fallback: proc_pid_rusage (may underreport for JIT-heavy processes like Node.js/V8)
        var rusage = rusage_info_v4()
        let ret = withUnsafeMutablePointer(to: &rusage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return ret == 0 ? rusage.ri_phys_footprint : 0
    }

    // MARK: - Process Name Helpers

    /// Reads the extended process name (pbi_name, up to 32 chars) via proc_bsdinfo.
    /// This field is updated by setproctitle()/libuv, so Node.js "next-server" etc. appear here.
    private func getProcessTitle(pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) > 0 else { return nil }

        // pbi_name is a C array — read it as a null-terminated string
        return withUnsafeBytes(of: info.pbi_name) { bytes -> String? in
            guard let base = bytes.baseAddress else { return nil }
            let str = String(cString: base.assumingMemoryBound(to: CChar.self))
            return str.isEmpty ? nil : str
        }
    }

    private func fallbackProcName(_ pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, 256)
        return String(cString: nameBuffer)
    }
}
