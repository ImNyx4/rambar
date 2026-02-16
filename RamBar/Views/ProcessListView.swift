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
