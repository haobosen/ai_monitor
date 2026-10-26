import SwiftUI
import AppKit

/// 任务完成时右上角出现的提示条：不依赖系统通知权限
struct ToastView: View {
    let task: AITask
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.completed)
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(task.provider) · 任务完成")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(task.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(task.projectName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(VisualEffectBackground(material: .hudWindow, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        )
        .padding(10)
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
