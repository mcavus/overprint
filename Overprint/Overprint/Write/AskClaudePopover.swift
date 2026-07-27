import SwiftUI

/// The inline "Ask Claude" popover: preset actions plus a freeform field, applying the
/// result to the current draft's body.
struct AskClaudePopover: View {
    @ObservedObject var ai: AIManager
    @ObservedObject var model: WriteModel
    @Binding var isPresented: Bool
    @Environment(\.openSettings) private var openSettings

    @State private var text = ""

    private let presets = [
        "Tighten the introduction",
        "Fix grammar and spelling",
        "Add a conclusion",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            if ai.isAvailable {
                inputRow
                stateContent
            } else {
                unavailable
            }
        }
        .padding(14)
        .frame(width: 320)
        .onDisappear { ai.resetState() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(OPColor.accent).frame(width: 18, height: 18)
                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(.white)
            }
            Text("Ask Claude").font(OPFont.ui(13, weight: .semibold)).foregroundStyle(OPColor.ink)
            Spacer()
            Text("edits this post").font(OPFont.mono(11)).foregroundStyle(OPColor.textFainter)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Rewrite the intro, fix grammar…", text: $text)
                .textFieldStyle(.plain)
                .font(OPFont.ui(13))
                .onSubmit { run(text) }
            Button { run(text) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(OPColor.accent))
            }
            .buttonStyle(.plain)
            .disabled(ai.state == .busy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.14)))
    }

    @ViewBuilder private var stateContent: some View {
        switch ai.state {
        case .idle:
            VStack(spacing: 3) {
                ForEach(presets, id: \.self) { preset in
                    Button { run(preset) } label: {
                        HStack(spacing: 9) {
                            Text("›").font(OPFont.mono(12)).foregroundStyle(OPColor.borderStrong)
                            Text(preset).font(OPFont.ui(12.5)).foregroundStyle(Color(hex: 0x3A3A3E))
                            Spacer()
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .busy:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Working…").font(OPFont.ui(12.5)).foregroundStyle(OPColor.textSecondary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
        case .done:
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(OPColor.ink).frame(width: 16, height: 16)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
                Text("Applied to your draft.").font(OPFont.ui(12.5)).foregroundStyle(OPColor.ink)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
        case .error(let message):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xC0392B))
                Text(message)
                    .font(OPFont.ui(12.5))
                    .foregroundStyle(OPColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Install Claude Code and sign in with your Claude subscription to use Ask Claude.")
                .font(OPFont.ui(12.5))
                .foregroundStyle(OPColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                isPresented = false
                openSettings()
            } label: {
                Text("Open Settings")
                    .font(OPFont.ui(12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(OPColor.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private func run(_ instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ai.state != .busy else { return }
        // Snapshot what we are editing before the await. This popover is not modal and the
        // request takes seconds, so the user can select another post or keep typing meanwhile.
        // Applying the result blindly would overwrite the wrong file, or clobber newer keystrokes.
        let target = model.selectedURL
        let body = model.currentBody()

        Task {
            guard let edited = await ai.edit(instruction: trimmed, body: body) else { return }

            guard model.selectedURL == target else {
                ai.state = .error("You switched posts while Claude was working, so nothing was changed.")
                return
            }
            guard model.currentBody() == body else {
                ai.state = .error("The draft changed while Claude was working, so nothing was changed.")
                return
            }

            model.applyEditedBody(edited)
            text = ""
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            ai.resetState()
            isPresented = false
        }
    }
}
