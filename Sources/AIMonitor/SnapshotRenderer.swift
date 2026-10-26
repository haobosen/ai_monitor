import AppKit
import SwiftUI

/// 离屏渲染，用于在没有录屏权限时检查界面（仅调试用，通过 --snapshot 触发）
enum SnapshotRenderer {

    @discardableResult
    static func capture(window: NSWindow, to url: URL) -> Bool {
        guard let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return false }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url)) != nil
    }

    @discardableResult
    static func capture<V: View>(_ view: V, size: NSSize, to url: URL) -> Bool {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()

        // 给 SwiftUI 一次布局 / 绘制机会
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))

        let ok = capture(window: window, to: url)
        window.orderOut(nil)
        return ok
    }
}
