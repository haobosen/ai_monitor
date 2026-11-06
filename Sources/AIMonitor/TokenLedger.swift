import Foundation
import Combine

/// 持久化 Token 增量账本：按本地日期累计“今日用量”，同时保留历史总用量。
///
/// 各适配器给出的是会话累计值，所以这里只记录每次刷新相对上次的增量；
/// 服务重启后通过 baselines 继续累加，不会把同一段用量重复计入。
final class TokenLedger: ObservableObject {

    static let shared = TokenLedger()

    @Published private(set) var todayTokens = 0
    @Published private(set) var historyTokens = 0

    private struct State: Codable {
        var version = 1
        var seeded = false
        var historyTokens = 0
        var days: [String: Int] = [:]
        var baselines: [String: Int] = [:]
    }

    private static let storageKey = "tokenUsageLedgerV1"
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var state: State
    private var lastDayKey: String

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
        lastDayKey = Self.dayKey(for: Date())
        todayTokens = state.days[lastDayKey] ?? 0
        historyTokens = state.historyTokens
    }

    /// 每次引擎刷新后调用，传入当前实际展示的任务（已按项目合并）。
    func record(tasks: [AITask], now: Date = Date()) {
        let dayKey = Self.dayKey(for: now)
        if dayKey != lastDayKey {
            lastDayKey = dayKey
            publish(dayKey: dayKey)
        }

        // 第一次拿到有 Token 的任务时，把已有会话累计值作为历史基线，
        // 避免功能启用前的用量全部丢失，也不把它们误算成“今日”。
        if !state.seeded {
            let tokenTasks = tasks.filter { $0.tokens != nil }
            guard !tokenTasks.isEmpty else { return }

            state.seeded = true
            state.historyTokens = max(state.historyTokens, tokenTasks.reduce(0) { $0 + ($1.tokens ?? 0) })
            for task in tokenTasks {
                state.baselines[task.id] = task.tokens ?? 0
            }
            save()
            publish(dayKey: dayKey)
            return
        }

        var changed = false
        for task in tasks {
            guard let current = task.tokens else { continue }
            let previous = state.baselines[task.id]

            if let previous {
                if current > previous {
                    addUsage(current - previous, dayKey: dayKey)
                    state.baselines[task.id] = current
                    changed = true
                } else if current < previous {
                    // 会话被重建/截断时只重置基线，不倒扣历史。
                    state.baselines[task.id] = current
                    changed = true
                }
            } else {
                // 新出现的任务先建立基线，避免把历史会话的一次性总量算进今天。
                state.baselines[task.id] = current
                changed = true
            }
        }

        if changed {
            save()
        }
        publish(dayKey: dayKey)
    }

    private func publish(dayKey: String) {
        let newToday = state.days[dayKey] ?? 0
        if todayTokens != newToday { todayTokens = newToday }
        if historyTokens != state.historyTokens { historyTokens = state.historyTokens }
    }

    private func addUsage(_ amount: Int, dayKey: String) {
        guard amount > 0 else { return }
        state.historyTokens += amount
        state.days[dayKey, default: 0] += amount
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
