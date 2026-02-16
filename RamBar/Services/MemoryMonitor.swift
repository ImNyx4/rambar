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

        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let free = total > used ? total - used : 0

        return SystemMemory(total: total, used: used, free: free, pressure: currentPressure)
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

    private func fetchProcesses() -> [ProcessMemory] {
        var pids = [pid_t](repeating: 0, count: 2048)
        let byteCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let pidCount = Int(byteCount) / MemoryLayout<pid_t>.size

        let runningApps = NSWorkspace.shared.runningApplications
        let appMap = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })

        var results: [ProcessMemory] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
            guard ret == size else { continue }

            let rss = UInt64(info.pti_resident_size)
            guard rss > 10_000_000 else { continue }

            let name: String
            let icon: NSImage?

            if let app = appMap[pid] {
                name = app.localizedName ?? "Unknown"
                icon = app.icon
            } else {
                var nameBuffer = [CChar](repeating: 0, count: 256)
                proc_name(pid, &nameBuffer, 256)
                name = String(cString: nameBuffer)
                icon = nil
            }

            guard !name.isEmpty else { continue }
            results.append(ProcessMemory(id: pid, name: name, memory: rss, icon: icon))
        }

        let grouped = groupHelperProcesses(results)
        return Array(grouped.sorted { $0.memory > $1.memory }.prefix(15))
    }

    private func groupHelperProcesses(_ processes: [ProcessMemory]) -> [ProcessMemory] {
        var groups: [String: (memory: UInt64, icon: NSImage?, pid: pid_t)] = [:]

        for proc in processes {
            let baseName = proc.name
                .replacingOccurrences(of: " Helper.*", with: "", options: .regularExpression)
                .replacingOccurrences(of: " Renderer", with: "")
                .replacingOccurrences(of: " GPU Process", with: "")

            if var existing = groups[baseName] {
                existing.memory += proc.memory
                if existing.icon == nil { existing.icon = proc.icon }
                groups[baseName] = existing
            } else {
                groups[baseName] = (proc.memory, proc.icon, proc.id)
            }
        }

        return groups.map { name, info in
            ProcessMemory(id: info.pid, name: name, memory: info.memory, icon: info.icon)
        }
    }
}
