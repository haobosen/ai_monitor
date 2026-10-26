import Foundation
import UserNotifications

/// 任务状态变化时发系统通知；同时把“新完成”的任务回传给浮窗做横幅提示
final class TaskNotifier: NSObject, UNUserNotificationCenterDelegate {

    private var lastStatuses: [String: TaskStatus] = [:]
    private var isFirstScan = true

    var isMuted = false

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.write("通知授权失败: \(error.localizedDescription)")
            } else {
                Log.write("通知授权: \(granted ? "已允许" : "被拒绝")")
            }
        }
    }

    /// 比对上一次状态，返回本次新完成的任务
    func process(_ tasks: [AITask]) -> [AITask] {
        var newlyCompleted: [AITask] = []
        let currentIDs = Set(tasks.map { $0.id })

        for task in tasks {
            let previous = lastStatuses[task.id]

            if previous != task.status {
                if task.status == .completed, let previous, previous != .completed {
                    newlyCompleted.append(task)
                    post(title: "✅ \(task.provider) 任务完成",
                         body: "\(task.title)\n\(task.projectName)",
                         id: task.id)
                } else if task.status == .failed, let previous, previous != .failed {
                    post(title: "❌ \(task.provider) 任务失败",
                         body: "\(task.title)\n\(task.projectName)",
                         id: task.id)
                } else if previous == nil, isFirstScan,
                          task.status == .completed,
                          Date().timeIntervalSince(task.updatedAt) < 180 {
                    // 应用刚启动时，把 3 分钟内刚结束的任务也提示一次
                    newlyCompleted.append(task)
                    post(title: "✅ \(task.provider) 任务完成",
                         body: "\(task.title)\n\(task.projectName)",
                         id: task.id)
                }
            }

            lastStatuses[task.id] = task.status
        }

        lastStatuses = lastStatuses.filter { currentIDs.contains($0.key) }
        isFirstScan = false
        return newlyCompleted
    }

    private func post(title: String, body: String, id: String) {
        guard !isMuted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(id)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.write("通知发送失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
