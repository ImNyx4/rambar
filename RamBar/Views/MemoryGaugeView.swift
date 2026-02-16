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
