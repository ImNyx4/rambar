# RamBar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that shows real-time RAM usage percentage, expandable to a frosted-glass popover with memory pressure gauge and per-app RAM breakdown.

**Architecture:** Native Swift + SwiftUI. `NSStatusItem` displays percentage in menu bar. `NSPopover` with SwiftUI content shows the expanded view. `MemoryMonitor` (ObservableObject) polls Mach APIs every 3s and publishes data reactively. No external dependencies.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, macOS 13+, xcodegen for project generation, xcodebuild for CLI builds.

**Design doc:** `docs/plans/2026-02-16-rambar-design.md`

---

### Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `RamBar/Info.plist`
- Create: `RamBar/RamBarApp.swift`
- Create: `RamBar/Assets.xcassets/Contents.json`
- Create: `RamBar/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `RamBarTests/RamBarTests.swift`

**Step 1: Install xcodegen**

Run: `brew install xcodegen`
Expected: xcodegen installs successfully

**Step 2: Create project.yml**

```yaml
name: RamBar
options:
  bundleIdPrefix: com.sihan
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
targets:
  RamBar:
    type: application
    platform: macOS
    sources:
      - path: RamBar
    settings:
      base:
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        PRODUCT_BUNDLE_IDENTIFIER: com.sihan.rambar
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        INFOPLIST_FILE: RamBar/Info.plist
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: "NO"
  RamBarTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: RamBarTests
    dependencies:
      - target: RamBar
    settings:
      base:
        SWIFT_VERSION: "5.9"
```

**Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>RamBar</string>
    <key>CFBundleDisplayName</key>
    <string>RamBar</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Sihan. All rights reserved.</string>
</dict>
</plist>
```

**Step 4: Create asset catalog**

Create `RamBar/Assets.xcassets/Contents.json`:
```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Create `RamBar/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 5: Create minimal app entry point**

`RamBar/RamBarApp.swift`:
```swift
import SwiftUI

@main
struct RamBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar controller will be set up in a later task
    }
}
```

**Step 6: Create placeholder test file**

`RamBarTests/RamBarTests.swift`:
```swift
import XCTest

final class RamBarTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

**Step 7: Generate Xcode project and build**

Run: `cd ~/Projects/rambar && xcodegen generate`
Expected: "Generated project RamBar.xcodeproj"

Run: `cd ~/Projects/rambar && xcodebuild build -project RamBar.xcodeproj -scheme RamBar -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED

**Step 8: Run tests**

Run: `cd ~/Projects/rambar && xcodebuild test -project RamBar.xcodeproj -scheme RamBarTests -destination 'platform=macOS' -quiet`
Expected: TEST SUCCEEDED

**Step 9: Commit**

```bash
cd ~/Projects/rambar
git add project.yml RamBar/ RamBarTests/ RamBar.xcodeproj/
git commit -m "scaffold: Xcode project with xcodegen, LSUIElement menu bar app"
```

---

### Task 2: Data Models + Byte Formatting

**Files:**
- Create: `RamBar/Models/SystemMemory.swift`
- Create: `RamBar/Models/ProcessMemory.swift`
- Create: `RamBar/Helpers/ByteFormatting.swift`
- Create: `RamBarTests/SystemMemoryTests.swift`
- Create: `RamBarTests/ByteFormattingTests.swift`

**Step 1: Write failing tests for SystemMemory**

`RamBarTests/SystemMemoryTests.swift`:
```swift
import XCTest
@testable import RamBar

final class SystemMemoryTests: XCTestCase {
    func testUsedPercentageCalculation() {
        let mem = SystemMemory(total: 16_000_000_000, used: 12_000_000_000, free: 4_000_000_000, pressure: .normal)
        XCTAssertEqual(mem.usedPercentage, 75)
    }

    func testUsedPercentageZeroTotal() {
        let mem = SystemMemory(total: 0, used: 0, free: 0, pressure: .normal)
        XCTAssertEqual(mem.usedPercentage, 0)
    }

    func testUsedPercentageRounding() {
        // 10/30 = 33.33...% → 33
        let mem = SystemMemory(total: 30_000_000_000, used: 10_000_000_000, free: 20_000_000_000, pressure: .normal)
        XCTAssertEqual(mem.usedPercentage, 33)
    }

    func testZeroMemory() {
        let mem = SystemMemory.zero
        XCTAssertEqual(mem.total, 0)
        XCTAssertEqual(mem.usedPercentage, 0)
    }
}
```

**Step 2: Write failing tests for ByteFormatting**

`RamBarTests/ByteFormattingTests.swift`:
```swift
import XCTest
@testable import RamBar

final class ByteFormattingTests: XCTestCase {
    func testGigabyteFormatting() {
        let bytes: UInt64 = 12_400_000_000 // ~11.55 GB
        let result = bytes.formattedBytes
        XCTAssertTrue(result.hasSuffix("GB"))
    }

    func testMegabyteFormatting() {
        let bytes: UInt64 = 890_000_000 // ~849 MB
        let result = bytes.formattedBytes
        XCTAssertTrue(result.hasSuffix("MB"))
    }

    func testExactOneGB() {
        let bytes: UInt64 = 1_073_741_824 // exactly 1 GiB
        XCTAssertEqual(bytes.formattedBytes, "1.0 GB")
    }

    func testSmallMB() {
        let bytes: UInt64 = 52_428_800 // 50 MiB
        XCTAssertEqual(bytes.formattedBytes, "50 MB")
    }

    func testZeroBytes() {
        let bytes: UInt64 = 0
        XCTAssertEqual(bytes.formattedBytes, "0 MB")
    }
}
```

**Step 3: Run tests to verify they fail**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild test -project RamBar.xcodeproj -scheme RamBarTests -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: FAIL — types not found

**Step 4: Implement models**

`RamBar/Models/SystemMemory.swift`:
```swift
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
```

`RamBar/Models/ProcessMemory.swift`:
```swift
import AppKit

struct ProcessMemory: Identifiable {
    let id: pid_t
    let name: String
    let memory: UInt64
    let icon: NSImage?
}
```

`RamBar/Helpers/ByteFormatting.swift`:
```swift
import Foundation

extension UInt64 {
    var formattedBytes: String {
        let gb = Double(self) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(self) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
```

**Step 5: Regenerate project and run tests**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild test -project RamBar.xcodeproj -scheme RamBarTests -destination 'platform=macOS' -quiet`
Expected: TEST SUCCEEDED (all 9 tests pass)

**Step 6: Commit**

```bash
cd ~/Projects/rambar
git add RamBar/Models/ RamBar/Helpers/ RamBarTests/SystemMemoryTests.swift RamBarTests/ByteFormattingTests.swift
git commit -m "feat: data models (SystemMemory, ProcessMemory) and byte formatting with tests"
```

---

### Task 3: MemoryMonitor Service — System Memory

**Files:**
- Create: `RamBar/Services/MemoryMonitor.swift`
- Create: `RamBarTests/MemoryMonitorTests.swift`

**Step 1: Write test for system memory fetch**

`RamBarTests/MemoryMonitorTests.swift`:
```swift
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
```

**Step 2: Run tests to verify they fail**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild test -project RamBar.xcodeproj -scheme RamBarTests -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: FAIL — MemoryMonitor not found

**Step 3: Implement MemoryMonitor**

`RamBar/Services/MemoryMonitor.swift`:
```swift
import Foundation
import AppKit
import Combine

class MemoryMonitor: ObservableObject {
    @Published var systemMemory: SystemMemory = .zero
    @Published var processes: [ProcessMemory] = []

    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var currentPressure: MemoryPressure = .normal

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
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
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
```

**Step 4: Regenerate project and run tests**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild test -project RamBar.xcodeproj -scheme RamBarTests -destination 'platform=macOS' -quiet`
Expected: TEST SUCCEEDED (all 14 tests pass)

**Step 5: Commit**

```bash
cd ~/Projects/rambar
git add RamBar/Services/ RamBarTests/MemoryMonitorTests.swift
git commit -m "feat: MemoryMonitor service with Mach API system memory and per-process collection"
```

---

### Task 4: MenuBarController + Status Item

**Files:**
- Create: `RamBar/MenuBarController.swift`
- Modify: `RamBar/RamBarApp.swift`

**Step 1: Create MenuBarController**

`RamBar/MenuBarController.swift`:
```swift
import AppKit
import SwiftUI
import Combine

class MenuBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let monitor: MemoryMonitor
    private var cancellable: AnyCancellable?

    init() {
        monitor = MemoryMonitor()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        popover.contentSize = NSSize(width: 300, height: 420)
        popover.behavior = .transient
        popover.animates = true

        // Placeholder view — will be replaced in Task 7
        popover.contentViewController = NSHostingController(
            rootView: Text("RamBar").frame(width: 300, height: 420)
        )

        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.title = "—%"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        cancellable = monitor.$systemMemory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] memory in
                self?.statusItem.button?.title = "\(memory.usedPercentage)%"
            }

        monitor.start()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

**Step 2: Wire up in AppDelegate**

Replace `RamBar/RamBarApp.swift`:
```swift
import SwiftUI

@main
struct RamBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }
}
```

**Step 3: Regenerate project, build, and run**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild build -project RamBar.xcodeproj -scheme RamBar -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED

Run manually: `open ~/Projects/rambar/build/Build/Products/Debug/RamBar.app` (or find in DerivedData)
Expected: Percentage appears in menu bar, clicking opens a placeholder popover

**Step 4: Commit**

```bash
cd ~/Projects/rambar
git add RamBar/MenuBarController.swift RamBar/RamBarApp.swift
git commit -m "feat: MenuBarController with NSStatusItem showing live RAM percentage"
```

---

### Task 5: MemoryGaugeView

**Files:**
- Create: `RamBar/Views/MemoryGaugeView.swift`

**Step 1: Create the circular gauge view**

`RamBar/Views/MemoryGaugeView.swift`:
```swift
import SwiftUI

struct MemoryGaugeView: View {
    let memory: SystemMemory

    private var pressureColor: Color {
        switch memory.pressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var pressureText: String {
        switch memory.pressure {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(pressureColor.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: Double(memory.usedPercentage) / 100.0)
                    .stroke(pressureColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: memory.usedPercentage)

                Text("\(memory.usedPercentage)%")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Memory")
                    .font(.system(size: 14, weight: .medium))

                HStack(spacing: 4) {
                    Text("Pressure:")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.secondary)

                    Text(pressureText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(pressureColor)
                }
            }
        }
    }
}
```

**Step 2: Build**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild build -project RamBar.xcodeproj -scheme RamBar -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
cd ~/Projects/rambar
git add RamBar/Views/MemoryGaugeView.swift
git commit -m "feat: MemoryGaugeView circular pressure gauge with animated ring"
```

---

### Task 6: ProcessListView

**Files:**
- Create: `RamBar/Views/ProcessListView.swift`

**Step 1: Create process row and list views**

`RamBar/Views/ProcessListView.swift`:
```swift
import SwiftUI

struct ProcessRow: View {
    let process: ProcessMemory

    var body: some View {
        HStack(spacing: 10) {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app")
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }

            Text(process.name)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(process.memory.formattedBytes)
                .font(.system(size: 12, weight: .light, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct ProcessListView: View {
    let processes: [ProcessMemory]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                    ProcessRow(process: process)
                        .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                }
            }
        }
    }
}
```

**Step 2: Build**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild build -project RamBar.xcodeproj -scheme RamBar -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
cd ~/Projects/rambar
git add RamBar/Views/ProcessListView.swift
git commit -m "feat: ProcessListView with app icons, sorted by RAM usage"
```

---

### Task 7: PopoverView Assembly + Glassy Styling

**Files:**
- Create: `RamBar/Views/PopoverView.swift`
- Modify: `RamBar/MenuBarController.swift` — replace placeholder with real view

**Step 1: Create PopoverView**

`RamBar/Views/PopoverView.swift`:
```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: MemoryMonitor
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(monitor: monitor, showSettings: $showSettings)
            } else {
                mainContent
            }
        }
        .frame(width: 300, height: 420)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Gauge
            MemoryGaugeView(memory: monitor.systemMemory)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)

            // Used / Free summary
            HStack {
                Text("Used: \(monitor.systemMemory.used.formattedBytes)")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Free: \(monitor.systemMemory.free.formattedBytes)")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider().opacity(0.15)

            // Process list
            ProcessListView(processes: monitor.processes)

            Divider().opacity(0.15)

            // Footer
            HStack {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
```

Note: `SettingsView` doesn't exist yet — create a stub so it compiles. It will be fully implemented in Task 8.

Create temporary stub `RamBar/Views/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: MemoryMonitor
    @Binding var showSettings: Bool

    var body: some View {
        VStack {
            Text("Settings")
            Button("Back") { showSettings = false }
        }
        .frame(width: 300, height: 420)
    }
}
```

**Step 2: Wire PopoverView into MenuBarController**

In `RamBar/MenuBarController.swift`, replace the placeholder line:
```swift
// Replace this:
popover.contentViewController = NSHostingController(
    rootView: Text("RamBar").frame(width: 300, height: 420)
)

// With this:
popover.contentViewController = NSHostingController(
    rootView: PopoverView(monitor: monitor)
)
```

**Step 3: Build and run**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild build -project RamBar.xcodeproj -scheme RamBar -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED

Run the app and verify: percentage in menu bar, click opens frosted popover with gauge + process list + footer.

**Step 4: Commit**

```bash
cd ~/Projects/rambar
git add RamBar/Views/PopoverView.swift RamBar/Views/SettingsView.swift RamBar/MenuBarController.swift
git commit -m "feat: PopoverView with gauge, process list, and footer; wired to menu bar"
```

---

### Task 8: SettingsView + Launch at Login

**Files:**
- Modify: `RamBar/Views/SettingsView.swift` — replace stub with full implementation

**Step 1: Implement full SettingsView**

Replace `RamBar/Views/SettingsView.swift`:
```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var monitor: MemoryMonitor
    @Binding var showSettings: Bool
    @AppStorage("refreshInterval") private var refreshInterval: Double = 3.0
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Button(action: { showSettings = false }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)

                Text("Settings")
                    .font(.system(size: 14, weight: .medium))

                Spacer()
            }
            .padding(.bottom, 8)

            // Launch at login
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, newValue in
                    updateLaunchAtLogin(newValue)
                }

            // Refresh interval
            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh Interval")
                    .font(.system(size: 12, weight: .medium))

                Picker("", selection: $refreshInterval) {
                    Text("1s").tag(1.0)
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .onChange(of: refreshInterval) { _, newValue in
                    monitor.refreshInterval = newValue
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 300, height: 420)
        .onAppear {
            // Sync monitor interval from stored preference
            monitor.refreshInterval = refreshInterval
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }
}
```

**Step 2: Build and run**

Run: `cd ~/Projects/rambar && xcodegen generate && xcodebuild build -project RamBar.xcodeproj -scheme RamBar -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED

Run app, click gear icon, verify settings panel shows toggle + segmented picker, back button works.

**Step 3: Run all tests**

Run: `cd ~/Projects/rambar && xcodebuild test -project RamBar.xcodeproj -scheme RamBarTests -destination 'platform=macOS' -quiet`
Expected: TEST SUCCEEDED (all 14 tests pass)

**Step 4: Commit**

```bash
cd ~/Projects/rambar
git add RamBar/Views/SettingsView.swift
git commit -m "feat: SettingsView with launch-at-login toggle and refresh interval picker"
```

---

### Task 9: Final Polish + Integration Verification

**Files:**
- Modify: `RamBar/Views/PopoverView.swift` (minor styling tweaks if needed)
- No new files

**Step 1: Run full test suite**

Run: `cd ~/Projects/rambar && xcodebuild test -project RamBar.xcodeproj -scheme RamBarTests -destination 'platform=macOS' -quiet`
Expected: TEST SUCCEEDED

**Step 2: Build release configuration**

Run: `cd ~/Projects/rambar && xcodebuild build -project RamBar.xcodeproj -scheme RamBar -configuration Release -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Manual verification checklist**

Launch the release build and verify:
- [ ] Percentage shows in menu bar, updates every 3 seconds
- [ ] No dock icon visible
- [ ] Click opens frosted-glass popover
- [ ] Circular gauge shows correct percentage with colored ring
- [ ] Memory pressure label shown (Normal/Warning/Critical)
- [ ] Used/Free summary line displays correctly
- [ ] Process list shows apps with icons, sorted by RAM
- [ ] Helper processes grouped under parent app
- [ ] Settings gear opens settings panel
- [ ] Back button returns to main view
- [ ] Launch at login toggle works
- [ ] Refresh interval picker changes update speed
- [ ] Quit button terminates app
- [ ] App uses < 25MB RSS (check in Activity Monitor)

**Step 4: Final commit**

```bash
cd ~/Projects/rambar
git add -A
git commit -m "chore: final polish and integration verification"
```

---

## Summary

| Task | Description | Tests |
|------|-------------|-------|
| 1 | Project scaffold + xcodegen | 1 placeholder |
| 2 | Data models + byte formatting | 9 unit tests |
| 3 | MemoryMonitor service | 5 integration tests |
| 4 | MenuBarController + status item | Build + manual verify |
| 5 | MemoryGaugeView | Build verify |
| 6 | ProcessListView | Build verify |
| 7 | PopoverView assembly | Build + manual verify |
| 8 | SettingsView + launch at login | Build + manual verify |
| 9 | Final polish + verification | Full suite + manual checklist |

**Total: 9 tasks, 14 automated tests, ~45 min estimated implementation time**
