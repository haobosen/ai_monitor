import Foundation
import Combine

/// 用户配置：监控哪些 AI、是否已完成初始化
final class AppConfig: ObservableObject {

    static let shared = AppConfig()

    private enum Key {
        static let enabled = "enabledProviders"
        static let onboarded = "hasOnboarded"
        static let muted = "notificationsMuted"
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var enabledProviders: Set<String>
    @Published private(set) var hasOnboarded: Bool
    @Published var notificationsMuted: Bool

    /// 首次运行默认勾选两个支持任务级监控的 AI
    static let defaultProviders: Set<String> = ["claude", "codex"]

    private init() {
        if let stored = defaults.array(forKey: Key.enabled) as? [String] {
            enabledProviders = Set(stored)
        } else {
            enabledProviders = Self.defaultProviders
        }
        hasOnboarded = defaults.bool(forKey: Key.onboarded)
        notificationsMuted = defaults.bool(forKey: Key.muted)
    }

    func isEnabled(_ id: String) -> Bool { enabledProviders.contains(id) }

    func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled {
            enabledProviders.insert(id)
        } else {
            enabledProviders.remove(id)
        }
        saveEnabled()
    }

    func applySelection(_ selection: Set<String>) {
        enabledProviders = selection
        saveEnabled()
    }

    func completeOnboarding(with selection: Set<String>) {
        enabledProviders = selection
        saveEnabled()
        hasOnboarded = true
        defaults.set(true, forKey: Key.onboarded)
    }

    func resetOnboarding() {
        hasOnboarded = false
        defaults.set(false, forKey: Key.onboarded)
    }

    func setMuted(_ muted: Bool) {
        notificationsMuted = muted
        defaults.set(muted, forKey: Key.muted)
    }

    private func saveEnabled() {
        defaults.set(Array(enabledProviders).sorted(), forKey: Key.enabled)
    }
}
