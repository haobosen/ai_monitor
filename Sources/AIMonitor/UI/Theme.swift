import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(red: 0.46, green: 0.55, blue: 1.0)
    static let running = Color(red: 0.35, green: 0.62, blue: 1.0)
    static let waiting = Color(red: 1.0, green: 0.69, blue: 0.22)
    static let failed = Color(red: 1.0, green: 0.40, blue: 0.40)
    static let completed = Color(red: 0.30, green: 0.80, blue: 0.55)

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
        case .waiting:   return waiting.opacity(0.10)
        case .failed:    return failed.opacity(0.08)
        default:         return Color.primary.opacity(0.045)
        }
    }

    static func rowStroke(for status: TaskStatus) -> Color {
        switch status {
        case .waiting: return waiting.opacity(0.35)
        case .failed:  return failed.opacity(0.25)
        default:       return Color.primary.opacity(0.06)
        }
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
