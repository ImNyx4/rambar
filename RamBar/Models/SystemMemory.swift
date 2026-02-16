import Foundation

struct SystemMemory {
    let total: UInt64
    let used: UInt64
    let free: UInt64
    let pressure: MemoryPressure

    var usedPercentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(used) / Double(total)) * 100)
    }

    static let zero = SystemMemory(total: 0, used: 0, free: 0, pressure: .normal)
}

enum MemoryPressure {
    case normal, warning, critical
}
