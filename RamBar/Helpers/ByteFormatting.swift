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
