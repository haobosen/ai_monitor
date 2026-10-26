import SwiftUI
import AppKit

// MARK: - 状态图标

struct StatusIcon: View {
    let status: TaskStatus
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if status == .running {
                Circle()
                    .fill(Theme.color(for: status).opacity(0.35))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulsing ? 1.55 : 0.85)
                    .opacity(pulsing ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulsing)
            }
            Circle()
                .fill(Theme.color(for: status).opacity(0.16))
                .frame(width: 22, height: 22)
            Image(systemName: status.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.color(for: status))
        }
        .frame(width: 24, height: 24)
        .onAppear { pulsing = true }
    }
}

// MARK: - 状态文字徽标

struct StatusPill: View {
    let status: TaskStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Theme.color(for: status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Theme.color(for: status).opacity(0.14))
            )
    }
}

// MARK: - 任务行

struct TaskRow: View {
    let task: AITask
    let now: Date

    private var relativeTime: String {
        RelativeTime.string(max(0, now.timeIntervalSince(task.updatedAt)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            StatusIcon(status: task.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    // 已完成任务也要清晰可读，统一用黑色
                    .foregroundStyle(task.status == .completed ? Color.black : Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Text(task.projectName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.accent.opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.accent.opacity(0.09)))

                    StatusPill(status: task.status)

                    Spacer(minLength: 2)

                    Text(relativeTime)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                }

                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.rowFill(for: task.status))
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.rowStroke(for: task.status), lineWidth: 0.8)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.color(for: task.status).opacity(task.status == .completed ? 0.55 : 0.9))
                .frame(width: 3)
                .padding(.vertical, 9)
                .padding(.leading, 1)
        }
        .help(task.sourcePath ?? task.title)
    }
}

// MARK: - 分组标题

struct GroupHeader: View {
    let provider: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.providerColor(provider))
                .frame(width: 6, height: 6)
            Text(provider)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 0.5)
                .background(Capsule().fill(Theme.accent.opacity(0.09)))
            Spacer()
        }
        .padding(.top, 6)
        .padding(.bottom, 1)
    }
}

// MARK: - 顶部统计

struct SummaryBar: View {
    let counts: TaskCounts

    var body: some View {
        HStack(spacing: 8) {
            chip(counts.running, "运行中", Theme.running)
            chip(counts.waiting, "需要操作", Theme.waiting)
            chip(counts.failed, "失败", Theme.failed)
            chip(counts.completed, "已完成", Theme.completed)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(value > 0 ? Theme.inkSecondary : Theme.inkTertiary)
            Text("\(value)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(value > 0 ? color : Theme.inkTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(value > 0 ? 0.9 : 0.6)))
        .overlay(
            Capsule().strokeBorder(color.opacity(value > 0 ? 0.28 : 0.10), lineWidth: 0.8)
        )
    }
}

// MARK: - 完成提示横幅

struct CompletionBanner: View {
    let task: AITask
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 17))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text("任务完成 · \(task.provider)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(task.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.completed, Theme.completed.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: Theme.completed.opacity(0.45), radius: 10, y: 3)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.55))
            Text("暂时没有发现 AI 任务")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink.opacity(0.75))
            Text("在 Claude Code / Codex / DeepSeek Harness 里开始一个任务，或到设置里勾选更多 AI。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
            Button("打开设置", action: onOpenSettings)
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
