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

        popover.contentViewController = NSHostingController(
            rootView: PopoverView(monitor: monitor)
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
