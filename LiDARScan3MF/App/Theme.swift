import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

/// 设计稿视觉系统：深色仪器风，单一强调色激光青
enum Theme {
    static let bg = Color(hex: 0x0C0E12)
    static let card = Color(hex: 0x16191F)
    static let chip = Color(hex: 0x2A3038)
    static let stroke = Color(hex: 0x262B33)
    static let accent = Color(hex: 0x35E2C2)
    static let text = Color(hex: 0xF2F4F7)
    static let text2 = Color(hex: 0x8E97A3)
    static let text3 = Color(hex: 0x5C6672)
    static let warn = Color(hex: 0xFFB454)

    static var data: Font { .system(size: 12, weight: .regular).monospaced() }
    static var dataAccent: Font { .system(size: 12, weight: .semibold).monospaced() }
}

extension Float {
    var fixed1: String { String(format: "%.1f", self) }
    var fixed2: String { String(format: "%.2f", self) }
}

extension Double {
    var fixed0: String { String(format: "%.0f", self) }
    var fixed1: String { String(format: "%.1f", self) }
    var fixed2: String { String(format: "%.2f", self) }
}

extension Int {
    var grouped: String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        return nf.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
