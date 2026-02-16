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
