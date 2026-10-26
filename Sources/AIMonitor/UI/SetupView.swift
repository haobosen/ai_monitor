import SwiftUI
import AppKit

// MARK: - 初始化 / 设置状态

final class SetupStore: ObservableObject {
    enum Mode {
        case onboarding
        case settings
    }

    let mode: Mode

    @Published var providers: [DetectedAI] = []
    @Published var selected: Set<String>
    @Published var isScanning = true
    @Published var lastScanAt: Date?
    private var hasScannedOnce = false

    var onFinish: ((Set<String>) -> Void)?
    var onSkip: (() -> Void)?
    var onToggle: ((String, Bool) -> Void)?

    init(mode: Mode) {
        self.mode = mode
        self.selected = AppConfig.shared.enabledProviders
    }

    var availableSupported: [DetectedAI] {
        providers.filter { $0.supported && $0.available }
    }

    var unavailableSupported: [DetectedAI] {
        providers.filter { $0.supported && !$0.available }
    }

    var apps: [DetectedAI] {
        providers.filter { !$0.supported }
    }

    var selectableCount: Int {
        availableSupported.count
    }

    func rescan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let discovered = AIProviderCatalog.discover()
            DispatchQueue.main.async {
                self.providers = discovered
                let selectable = Set(discovered.filter { $0.supported && $0.available }.map { $0.id })
                self.selected = self.selected.intersection(selectable)
                if self.mode == .onboarding, !self.hasScannedOnce, self.selected.isEmpty {
                    // 只有首次扫描时默认勾选，用户手动清空后重新扫描不会覆盖
                    self.selected = selectable
                }
                self.hasScannedOnce = true
                self.isScanning = false
                self.lastScanAt = Date()
            }
        }
    }

    func toggle(_ id: String, _ isOn: Bool) {
        if isOn { selected.insert(id) } else { selected.remove(id) }
        if mode == .settings {
            onToggle?(id, isOn)
        }
    }

    func finish() {
        onFinish?(selected)
    }
}

// MARK: - 选择界面

struct SetupView: View {
    @StateObject private var store: SetupStore
    private let onFinish: (Set<String>) -> Void
    private let onSkip: () -> Void
    private let onToggle: (String, Bool) -> Void

    init(mode: SetupStore.Mode,
         onFinish: @escaping (Set<String>) -> Void,
         onSkip: @escaping () -> Void,
         onToggle: @escaping (String, Bool) -> Void) {
        _store = StateObject(wrappedValue: SetupStore(mode: mode))
        self.onFinish = onFinish
        self.onSkip = onSkip
        self.onToggle = onToggle
    }

    private var isOnboarding: Bool { store.mode == .onboarding }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isScanning {
                scanningState
            } else {
                providerList
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.onFinish = onFinish
            store.onSkip = onSkip
            store.onToggle = onToggle
            if store.providers.isEmpty { store.rescan() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Color(red: 0.65, green: 0.45, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isOnboarding ? "先选择要监控的 AI" : "监控设置")
                    .font(.system(size: 17, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var subtitle: String {
        if store.isScanning { return "正在扫描本机的 AI 工具…" }
        if isOnboarding {
            return "已检测到 \(store.selectableCount) 个可监控的 AI，勾选后进入浮窗监控"
        }
        return "勾选需要出现在浮窗和菜单栏里的 AI，取消勾选即移除"
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("正在扫描电脑上的 AI 工具…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("检查 Claude Code、Codex 会话目录以及命令行 AI 工具")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var providerList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 7) {
                if !store.availableSupported.isEmpty {
                    sectionTitle("可以监控")
                    ForEach(store.availableSupported) { ai in
                        row(for: ai, enabled: true, available: true)
                    }
                }

                if !store.unavailableSupported.isEmpty {
                    sectionTitle("未检测到")
                        .padding(.top, 6)
                    ForEach(store.unavailableSupported) { ai in
                        row(for: ai, enabled: false, available: false)
                    }
                }

                if !store.apps.isEmpty {
                    sectionTitle("已安装的桌面应用")
                        .padding(.top, 6)
                    ForEach(store.apps) { ai in
                        row(for: ai, enabled: false, available: true)
                    }
                }

                if store.selectableCount == 0 {
                    VStack(spacing: 6) {
                        Text("没有检测到可监控的 AI")
                            .font(.system(size: 12, weight: .medium))
                        Text("请确认 Claude Code 或 Codex 已经在这台电脑上使用过，然后重新扫描。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func row(for ai: DetectedAI, enabled: Bool, available: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Toggle("", isOn: Binding(
                get: { store.selected.contains(ai.id) },
                set: { store.toggle(ai.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!enabled)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ai.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(available ? .primary : .secondary)
                    Text(ai.categoryLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ai.supported ? Theme.accent : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(
                            ai.supported ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.06)
                        ))
                }
                Text(ai.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(available ? 0.04 : 0.02))
        )
        .opacity(available || ai.supported ? 1 : 0.65)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                store.rescan()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if let last = store.lastScanAt {
                Text("上次扫描 \(DateFormatter.localizedString(from: last, dateStyle: .none, timeStyle: .short))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isOnboarding {
                Button("稍后设置") { store.onSkip?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Button(isOnboarding ? "开始监控" : "完成") {
                store.finish()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.regular)
            .disabled(isOnboarding && store.selected.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.02))
    }
}
