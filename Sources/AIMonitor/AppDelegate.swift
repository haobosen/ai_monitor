import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let config = AppConfig.shared
    private let engine = MonitorEngine()
    private let notifier = TaskNotifier()
    private let store = TaskStore()
    private let toastController = CompletionToastController()

    private var panelController: PanelController!
    private var mainWindowController: MainWindowController!
    private var menuBarController: MenuBarController!
    private var setupWindowController: SetupWindowController?

    private var isSnapshotMode: Bool { CommandLine.arguments.contains("--snapshot") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.write("应用启动，已启用: \(config.enabledProviders.sorted())")

        mainWindowController = MainWindowController(
            store: store,
            onRefresh: { [weak self] in self?.engine.refresh() },
            onSettings: { [weak self] in self?.presentSetup(mode: .settings) }
        )
        mainWindowController.onVisibilityChange = { [weak self] visible in
            guard let self, visible else { return }
            self.store.clearUnread()
            self.menuBarController?.refreshIcon()
            Log.write("主界面可见性: \(visible)")
        }

        panelController = PanelController(
            store: store,
            onOpenMain: { [weak self] _ in self?.openMain() }
        )
        panelController.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            if visible {
                self.store.clearUnread()
                self.menuBarController?.refreshIcon()
            }
            Log.write("浮窗可见性: \(visible)")
        }

        menuBarController = MenuBarController(store: store, actions: MenuBarController.Actions(
            openMain: { [weak self] in self?.openMain() },
            togglePanel: { [weak self] in self?.panelController.toggle() },
            isPanelVisible: { [weak self] in self?.panelController.isVisible ?? false },
            openSettings: { [weak self] in self?.presentSetup(mode: .settings) },
            refresh: { [weak self] in self?.engine.refresh() },
            toggleMute: { [weak self] in
                guard let self else { return }
                self.config.setMuted(!self.config.notificationsMuted)
                self.notifier.isMuted = self.config.notificationsMuted
            },
            isMuted: { [weak self] in self?.config.notificationsMuted ?? false },
            quit: { NSApp.terminate(nil) },
            selectTask: { [weak self] _ in self?.openMain() }
        ))

        notifier.isMuted = config.notificationsMuted

        if CommandLine.arguments.contains("--dump-menu") {
            print(menuBarController.debugItemTitles().joined(separator: "\n"))
            NSApp.terminate(nil)
            return
        }

        engine.onUpdate = { [weak self] tasks in
            guard let self else { return }
            self.store.apply(tasks)
            self.menuBarController.refreshIcon()

            let newlyCompleted = self.notifier.process(tasks)
            for task in newlyCompleted {
                self.store.showCompletion(task)
                self.store.highlight(provider: task.provider)
                if !self.isSnapshotMode, !self.mainWindowController.isVisible {
                    self.toastController.show(task: task, muted: self.config.notificationsMuted) { [weak self] in
                        self?.openMain()
                    }
                }
            }
            if !newlyCompleted.isEmpty {
                if self.panelController.isVisible || self.mainWindowController.isVisible {
                    self.store.clearUnread()
                }
                self.menuBarController.refreshIcon()
            }
        }

        engine.setEnabledProviders(config.enabledProviders)
        engine.start(interval: 2.0)

        if config.hasOnboarded {
            if !isSnapshotMode { notifier.requestAuthorization() }
            panelController.show()
        } else {
            presentSetup(mode: .onboarding)
        }

        // 调试：启动后直接打开主界面
        if CommandLine.arguments.contains("--main") {
            openMain()
        }

        // 调试：展示完成提示条
        if CommandLine.arguments.contains("--test-toast") {
            toastController.show(task: Self.demoTasks()[0], muted: true) {}
        }

        if isSnapshotMode {
            if CommandLine.arguments.contains("--settings") {
                presentSetup(mode: .settings)
            }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                self?.performSnapshot()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        Log.write("应用退出")
    }

    // MARK: - 调试：离屏截图

    private func performSnapshot() {
        let directory = Self.snapshotDirectory()
        var report: [String] = []

        let visibleWindows = NSApp.windows.filter { $0.isVisible }
        for (index, window) in visibleWindows.enumerated() {
            let name = "window-\(index).png"
            let ok = SnapshotRenderer.capture(window: window, to: directory.appendingPathComponent(name))
            report.append("\(name):\(ok) \(Int(window.frame.width))x\(Int(window.frame.height))")
        }

        let realStore = TaskStore()
        realStore.apply(store.tasks.isEmpty ? MonitorEngine.scanAll() : store.tasks)
        let realRows = CompactRows.models(tasks: realStore.tasks, enabled: AppConfig.shared.enabledProviders)
        let compactSize = CompactLayout.panelSize(rows: realRows.count)
        let realOK = SnapshotRenderer.capture(
            CompactView(store: realStore, actions: PanelActions()),
            size: compactSize,
            background: .clear,
            to: directory.appendingPathComponent("compact-real.png")
        )
        report.append("compact-real:\(realOK) rows=\(realRows.count) tasks=\(realStore.tasks.count)")

        let demoStore = TaskStore()
        let demoTasks = Self.demoTasks()
        demoStore.apply(demoTasks)
        demoStore.showCompletion(demoTasks[0])
        demoStore.highlight(provider: "Claude Code")
        let demoRows = CompactRows.models(tasks: demoStore.tasks, enabled: AppConfig.shared.enabledProviders)
        let demoOK = SnapshotRenderer.capture(
            CompactView(store: demoStore, actions: PanelActions()),
            size: CompactLayout.panelSize(rows: demoRows.count),
            background: .clear,
            to: directory.appendingPathComponent("compact-demo.png")
        )
        report.append("compact-demo:\(demoOK) rows=\(demoRows.count)")

        let toastOK = SnapshotRenderer.capture(
            ToastView(task: demoTasks[0], onOpen: {}, onClose: {}),
            size: NSSize(width: 340, height: 116),
            background: .clear,
            to: directory.appendingPathComponent("toast-demo.png")
        )
        report.append("toast-demo:\(toastOK)")

        let mainOK = SnapshotRenderer.capture(
            MainView(store: demoStore, onRefresh: {}, onSettings: {}),
            size: NSSize(width: 720, height: 600),
            to: directory.appendingPathComponent("main-demo.png")
        )
        report.append("main-demo:\(mainOK)")

        Log.write("snapshot: " + report.joined(separator: " | "))
        NSApp.terminate(nil)
    }

    private static func snapshotDirectory() -> URL {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), args.count > index + 1 {
            return URL(fileURLWithPath: args[index + 1])
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aimonitor-snapshots")
    }

    private static func demoTasks() -> [AITask] {
        let now = Date()
        return [
            AITask(id: "demo:waiting", provider: "Claude Code",
                   title: "等待确认：执行 npm run build 前需要授权",
                   project: "/Users/haobosen/projects/web-app", status: .waiting,
                   detail: "claude-sonnet-4.5 · 等待工具确认", updatedAt: now.addingTimeInterval(-42),
                   pid: 4321, sourcePath: nil),
            AITask(id: "demo:running", provider: "Claude Code",
                   title: "重构登录页表单校验逻辑，并补充单元测试",
                   project: "/Users/haobosen/projects/web-app", status: .running,
                   detail: "claude-sonnet-4.5 · 12 秒前活跃", updatedAt: now.addingTimeInterval(-12),
                   pid: 4321, sourcePath: nil),
            AITask(id: "demo:running2", provider: "Codex",
                   title: "把桌面上的视频素材剪成 20 秒带货短片",
                   project: "/Users/haobosen/Desktop/视频素材", status: .running,
                   detail: "gpt-6.1-sol · 1 分钟前活跃", updatedAt: now.addingTimeInterval(-60),
                   pid: nil, sourcePath: nil),
            AITask(id: "demo:failed", provider: "Codex",
                   title: "生成数据大屏对比维度接口联调",
                   project: "/Users/haobosen/sanjieke/b.study.sanjieke.cn.fe", status: .failed,
                   detail: "gpt-6.1-sol · 运行出错", updatedAt: now.addingTimeInterval(-320),
                   pid: nil, sourcePath: nil),
            AITask(id: "demo:completed", provider: "Claude Code",
                   title: "根据 Figma 设计稿开发公司信息页面",
                   project: "/Users/haobosen/sanjieke/b.manage.sanjike.cn.fe", status: .completed,
                   detail: "DeepSeek-V4.1 · 已完成", updatedAt: now.addingTimeInterval(-600),
                   pid: nil, sourcePath: nil),
        ]
    }

    // MARK: - 主界面 / 设置

    private func openMain() {
        mainWindowController.show()
        store.clearUnread()
        menuBarController?.refreshIcon()
    }

    private func presentSetup(mode: SetupStore.Mode) {
        if let existing = setupWindowController {
            existing.present()
            return
        }

        let isOnboarding = (mode == .onboarding)

        let controller = SetupWindowController(
            mode: mode,
            onFinish: { [weak self] selection in
                guard let self else { return }
                if isOnboarding {
                    self.config.completeOnboarding(with: selection)
                    self.engine.setEnabledProviders(selection)
                    self.dismissSetup()
                    self.panelController.show()
                    self.notifier.requestAuthorization()
                    Log.write("初始化完成，监控: \(selection.sorted())")
                } else {
                    self.config.applySelection(selection)
                    self.engine.setEnabledProviders(selection)
                    self.dismissSetup()
                    Log.write("设置更新，监控: \(selection.sorted())")
                }
            },
            onSkip: { [weak self] in
                guard let self else { return }
                self.config.completeOnboarding(with: self.config.enabledProviders)
                self.engine.setEnabledProviders(self.config.enabledProviders)
                self.dismissSetup()
                self.panelController.show()
                self.notifier.requestAuthorization()
            },
            onToggle: { [weak self] id, isOn in
                guard let self else { return }
                self.config.setEnabled(id, isOn)
                self.engine.setEnabledProviders(self.config.enabledProviders)
            },
            onUserClose: { [weak self] in
                guard let self else { return }
                self.setupWindowController = nil
                if !self.config.hasOnboarded {
                    self.config.completeOnboarding(with: self.config.enabledProviders)
                    self.engine.setEnabledProviders(self.config.enabledProviders)
                    self.panelController.show()
                    self.notifier.requestAuthorization()
                }
            }
        )

        setupWindowController = controller
        controller.present()
        Log.write("打开设置窗口: \(mode == .onboarding ? "初始化" : "设置")")
    }

    private func dismissSetup() {
        setupWindowController?.dismiss()
        setupWindowController = nil
    }
}
