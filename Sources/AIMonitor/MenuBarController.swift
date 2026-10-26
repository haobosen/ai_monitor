import AppKit

/// 菜单栏图标 + 下拉菜单：列出各 AI 的任务、显示/隐藏浮窗、设置、退出
final class MenuBarController: NSObject, NSMenuDelegate {

    struct Actions {
        var openMain: () -> Void = {}
        var togglePanel: () -> Void = {}
        var isPanelVisible: () -> Bool = { false }
        var openSettings: () -> Void = {}
        var refresh: () -> Void = {}
        var toggleMute: () -> Void = {}
        var isMuted: () -> Bool = { false }
        var quit: () -> Void = {}
        var selectTask: (String) -> Void = { _ in }
    }

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let store: TaskStore
    private var actions: Actions

    init(store: TaskStore, actions: Actions) {
        self.store = store
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        menu.delegate = self
        statusItem.menu = menu
        Log.write("菜单栏图标已创建: \(statusItem.button != nil)")
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 任务监控")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeft
        button.toolTip = "AI 任务监控"
        refreshIcon()
    }

    /// 有未读完成数时在图标右侧显示数字
    func refreshIcon() {
        guard let button = statusItem.button else { return }
        let unread = store.unreadCompletions
        if unread > 0 {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            button.attributedTitle = NSAttributedString(string: " \(unread)", attributes: attributes)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
        button.toolTip = unread > 0
            ? "AI 任务监控 · \(unread) 个任务已完成"
            : "AI 任务监控"
    }

    // MARK: - 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let counts = store.counts
        let header = NSMenuItem(
            title: "AI 任务监控 · \(counts.running + counts.waiting) 进行中",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if store.tasks.isEmpty {
            let empty = NSMenuItem(title: "暂无 AI 任务", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for group in store.groups {
                let groupItem = NSMenuItem(title: group.provider, action: nil, keyEquivalent: "")
                groupItem.isEnabled = false
                menu.addItem(groupItem)

                for task in group.tasks {
                    let title = "\(task.status.emoji) \(AITask.truncate(task.title, 34))"
                    let item = NSMenuItem(title: title, action: #selector(handleSelectTask(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = task.id
                    item.toolTip = "\(task.status.label) · \(task.projectName)\n\(task.detail)"
                    item.indentationLevel = 1
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(.separator())

        let mainItem = NSMenuItem(title: "打开主界面", action: #selector(handleOpenMain), keyEquivalent: "o")
        mainItem.target = self
        menu.addItem(mainItem)

        let toggleTitle = actions.isPanelVisible() ? "隐藏浮窗" : "显示浮窗"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleTogglePanel), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(handleRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let muteItem = NSMenuItem(title: "静音通知", action: #selector(handleToggleMute), keyEquivalent: "")
        muteItem.target = self
        muteItem.state = actions.isMuted() ? .on : .off
        menu.addItem(muteItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(handleSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 AI Monitor", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// 调试用：返回当前菜单项标题
    func debugItemTitles() -> [String] {
        menuNeedsUpdate(menu)
        return menu.items.map { $0.isSeparatorItem ? "---" : $0.title }
    }

    // MARK: - 动作

    @objc private func handleOpenMain() { actions.openMain() }
    @objc private func handleTogglePanel() { actions.togglePanel() }
    @objc private func handleRefresh() { actions.refresh() }
    @objc private func handleToggleMute() { actions.toggleMute() }
    @objc private func handleSettings() { actions.openSettings() }
    @objc private func handleQuit() { actions.quit() }

    @objc private func handleSelectTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        actions.selectTask(id)
    }
}
