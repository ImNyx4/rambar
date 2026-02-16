import XCTest
@testable import RamBar

final class MemoryMonitorTests: XCTestCase {
    func testFetchSystemMemoryReturnsNonZero() {
        let monitor = MemoryMonitor()
        monitor.refresh()
        XCTAssertGreaterThan(monitor.systemMemory.total, 0, "Total RAM should be > 0")
        XCTAssertGreaterThan(monitor.systemMemory.used, 0, "Used RAM should be > 0")
        XCTAssertLessThanOrEqual(monitor.systemMemory.used, monitor.systemMemory.total)
    }

    func testUsedPercentageIsReasonable() {
        let monitor = MemoryMonitor()
        monitor.refresh()
        XCTAssertGreaterThan(monitor.systemMemory.usedPercentage, 0)
        XCTAssertLessThanOrEqual(monitor.systemMemory.usedPercentage, 100)
    }

    func testFetchProcessesReturnsNonEmpty() {
        let monitor = MemoryMonitor()
        monitor.refresh()
        XCTAssertFalse(monitor.processes.isEmpty, "Should find at least one process")
    }

    func testProcessesAreSortedByMemoryDescending() {
        let monitor = MemoryMonitor()
        monitor.refresh()
        guard monitor.processes.count >= 2 else { return }
        for i in 0..<(monitor.processes.count - 1) {
            XCTAssertGreaterThanOrEqual(
                monitor.processes[i].memory,
                monitor.processes[i + 1].memory,
                "Processes should be sorted by memory descending"
            )
        }
    }

    func testProcessesFilteredAboveThreshold() {
        let monitor = MemoryMonitor()
        monitor.refresh()
        for proc in monitor.processes {
            XCTAssertGreaterThan(proc.memory, 10_000_000, "All processes should be > 10MB")
        }
    }
}
