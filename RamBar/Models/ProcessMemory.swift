import AppKit

struct ProcessMemory: Identifiable {
    let id: pid_t
    let name: String
    let memory: UInt64
    let icon: NSImage?
}
