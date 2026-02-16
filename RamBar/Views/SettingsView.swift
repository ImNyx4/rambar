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
                .onChange(of: launchAtLogin) { newValue in
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
                .onChange(of: refreshInterval) { newValue in
                    monitor.refreshInterval = newValue
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 300, height: 420)
        .onAppear {
            // Sync monitor interval from stored preference (also done at startup in MenuBarController)
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
