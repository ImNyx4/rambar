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

        let free = UInt64(stats.free_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let available = free + inactive + speculative + purgeable
        let used = total > available ? total - available : 0

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

            var rusage = rusage_info_v4()
            let ret = withUnsafeMutablePointer(to: &rusage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard ret == 0 else { continue }

            let footprint = rusage.ri_phys_footprint
            guard footprint > 10_000_000 else { continue }

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
            results.append(ProcessMemory(id: pid, name: name, memory: footprint, icon: icon))
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
