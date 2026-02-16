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
