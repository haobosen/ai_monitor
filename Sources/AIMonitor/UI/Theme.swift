import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(red: 0.46, green: 0.55, blue: 1.0)
    static let running = Color(red: 0.35, green: 0.62, blue: 1.0)
    static let waiting = Color(red: 1.0, green: 0.69, blue: 0.22)
    static let failed = Color(red: 1.0, green: 0.40, blue: 0.40)
    static let completed = Color(red: 0.30, green: 0.80, blue: 0.55)

    // 主界面浅色画布：白底带一点蓝紫，不再使用系统灰色
    static let canvasTop = Color(red: 0.985, green: 0.99, blue: 1.0)
    static let canvasBottom = Color(red: 0.945, green: 0.96, blue: 0.995)
    static let card = Color.white
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.18)

    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 500
    static let outerMargin: CGFloat = 18

    static func color(for status: TaskStatus) -> Color {
        switch status {
        case .running:   return running
        case .waiting:   return waiting
        case .failed:    return failed
        case .completed: return completed
        }
    }

    static func rowFill(for status: TaskStatus) -> Color {
        switch status {
        case .waiting:   return waiting.opacity(0.045)
        case .failed:    return failed.opacity(0.045)
        default:         return card
        }
    }

    static func rowStroke(for status: TaskStatus) -> Color {
        switch status {
        case .waiting: return waiting.opacity(0.28)
        case .failed:  return failed.opacity(0.24)
        case .running: return running.opacity(0.16)
        case .completed: return completed.opacity(0.14)
        }
    }

    /// 不同 AI 用不同色点，分组时更容易扫读
    static func providerColor(_ provider: String) -> Color {
        if provider.contains("Claude") { return Color(red: 0.90, green: 0.48, blue: 0.30) }
        if provider.contains("Codex") { return Color(red: 0.36, green: 0.44, blue: 0.62) }
        if provider.contains("DeepSeek") { return Color(red: 0.25, green: 0.55, blue: 0.92) }
        return accent
    }
}

/// 毛玻璃背景
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
