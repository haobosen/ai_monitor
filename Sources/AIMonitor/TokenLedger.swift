import Foundation
import Combine

/// 持久化 Token 增量账本：记录启用统计以来的历史总用量。
///
/// 各适配器给出的是会话累计值，所以这里只记录每次刷新相对上次的增量；
/// 服务重启后通过 baselines 继续累加，不会把同一段用量重复计入。
final class TokenLedger: ObservableObject {

    static let shared = TokenLedger()

    @Published private(set) var historyTokens = 0

    private struct State: Codable {
        var version = 1
        var seeded = false
        var historyTokens = 0
        var baselines: [String: Int] = [:]
    }

    private static let storageKey = "tokenUsageLedgerV1"
    private var state: State

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
        historyTokens = state.historyTokens
    }

    /// 每次引擎刷新后调用，传入当前实际展示的任务（已按项目合并）。
    func record(tasks: [AITask]) {
        // 第一次拿到有 Token 的任务时，把已有会话累计值作为历史基线，
        // 避免功能启用前的用量全部丢失。
        if !state.seeded {
            let tokenTasks = tasks.filter { $0.tokens != nil }
            guard !tokenTasks.isEmpty else { return }

            state.seeded = true
            state.historyTokens = max(state.historyTokens, tokenTasks.reduce(0) { $0 + ($1.tokens ?? 0) })
            for task in tokenTasks {
                state.baselines[task.id] = task.tokens ?? 0
            }
            save()
            publish()
            return
        }

        var changed = false
        for task in tasks {
            guard let current = task.tokens else { continue }
            let previous = state.baselines[task.id]

            if let previous {
                if current > previous {
                    state.historyTokens += current - previous
                    state.baselines[task.id] = current
                    changed = true
                } else if current < previous {
                    // 会话被重建/截断时只重置基线，不倒扣历史。
                    state.baselines[task.id] = current
                    changed = true
                }
            } else {
                // 新出现的任务先建立基线，避免把历史会话的一次性总量重复计入。
                state.baselines[task.id] = current
                changed = true
            }
        }

        if changed {
            save()
        }
        publish()
    }

    private func publish() {
        if historyTokens != state.historyTokens {
            historyTokens = state.historyTokens
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
