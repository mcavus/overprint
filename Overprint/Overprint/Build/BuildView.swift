import SwiftUI
import AppKit

/// Build mode: the assistant pane (empty state with suggestion chips, or the streaming
/// transcript) on the left, and the shared live preview with browser chrome on the right.
struct BuildView: View {
    @ObservedObject var model: BuildModel
    @ObservedObject var server: ServerManager
    @ObservedObject var ai: AIManager

    private let scrollAnchor = "op-transcript-bottom"

    private let suggestions: [(label: String, prompt: String)] = [
        ("A minimal personal blog", "Build a minimal personal blog with an editorial theme and dark mode."),
        ("A photography journal", "Build a photography journal with large images and a clean grid."),
        ("A developer changelog", "Build a developer changelog with dated entries and tags."),
    ]

    var body: some View {
        HStack(spacing: 0) {
            assistantPane
            previewPane
        }
    }

    // MARK: Assistant pane

    private var assistantPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Assistant")
                    .font(OPFont.mono(11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(OPColor.textFaint)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
            .overlay(alignment: .bottom) { Rectangle().fill(OPColor.hairline).frame(height: 1) }

            ScrollViewReader { proxy in
                ScrollView {
                    if model.hasStarted {
                        transcript
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: model.turns.count) { _ in
                    withAnimation { proxy.scrollTo(scrollAnchor, anchor: .bottom) }
                }
            }

            composer
        }
        .frame(width: 432)
        .background(OPColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(OPColor.hairline).frame(width: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image("overprint-mark")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .padding(.bottom, 18)
            Text("Describe your site")
                .font(OPFont.ui(17, weight: .semibold))
                .foregroundStyle(OPColor.ink)
                .padding(.bottom, 6)
            Text("Tell Claude what to build. It scaffolds the project, applies a theme, and serves it locally.")
                .font(OPFont.ui(13))
                .foregroundStyle(OPColor.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
                .padding(.bottom, 22)

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.label) { item in
                    SuggestionChip(label: item.label, enabled: ai.isAvailable) { model.useSuggestion(item.prompt) }
                }
            }
            .frame(maxWidth: 320)

            if !ai.isAvailable {
                Text("Install Claude Code and sign in with your Claude subscription to start building.")
                    .font(OPFont.ui(12))
                    .foregroundStyle(OPColor.textFainter)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var transcript: some View {
        VStack(spacing: 22) {
            ForEach(model.turns) { turn in
                turnView(turn)
            }
            Color.clear.frame(height: 1).id(scrollAnchor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func turnView(_ turn: BuildModel.Turn) -> some View {
        VStack(spacing: 14) {
            HStack {
                Spacer(minLength: 44)
                Text(turn.prompt)
                    .font(OPFont.ui(13.5))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(OPColor.accent, in: BubbleShape(tail: .topRight))
            }

            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle().fill(OPColor.accent).frame(width: 26, height: 26)
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 10) {
                    assistantBubble(leadText(turn))
                    if !turn.steps.isEmpty {
                        stepsCard(turn.steps)
                    }
                    if turn.isDone, turn.errorMessage == nil {
                        assistantBubble(doneText(turn), shape: BubbleShape(tail: .none))
                    }
                    if let error = turn.errorMessage {
                        errorBubble(error)
                    }
                }
            }
        }
    }

    private func leadText(_ turn: BuildModel.Turn) -> String {
        if turn.errorMessage != nil { return "I couldn't finish that:" }
        switch (turn.kind, turn.isDone) {
        case (.scaffold, false): return "On it. Scaffolding your site:"
        case (.scaffold, true): return "Done. Here's what I set up:"
        case (.change, false): return "On it. Making that change:"
        case (.change, true): return "Done. Here's what changed:"
        }
    }

    private func doneText(_ turn: BuildModel.Turn) -> String {
        // An open-ended turn reports what it actually did; a scaffold turn gets the intro copy.
        if let summary = turn.summary { return summary }
        let port = turn.servedPort ?? server.port
        return "Your site is running at localhost:\(port). Switch to Write to edit the posts."
    }

    private func assistantBubble(_ text: String, shape: BubbleShape = BubbleShape(tail: .topLeft)) -> some View {
        Text(text)
            .font(OPFont.ui(13.5))
            .foregroundStyle(Color(hex: 0x2A2A2E))
            .lineSpacing(2)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(OPColor.surface5, in: shape)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0xD03A2E))
            Text(text)
                .font(OPFont.ui(13))
                .foregroundStyle(Color(hex: 0x8A2A22))
                .lineSpacing(2)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color(hex: 0xFDECEA), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepsCard(_ steps: [BuildModel.Step]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                StepRow(step: step)
                if index < steps.count - 1 {
                    Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1)
                }
            }
        }
        .background(OPColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.09)))
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(composerPlaceholder, text: $model.composer, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(OPFont.ui(13.5))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1...4)
                    .onSubmit { model.send() }
                    .disabled(composerDisabled)

                Button { model.send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(OPColor.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(composerDisabled || model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(composerDisabled ? 0.5 : 1)
            }
            .padding(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 7))
            .background(OPColor.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.14)))
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .overlay(alignment: .top) { Rectangle().fill(OPColor.hairline).frame(height: 1) }
    }

    private var composerDisabled: Bool {
        model.isRunning || !ai.isAvailable
    }

    private var composerPlaceholder: String {
        if !ai.isAvailable { return "Install Claude Code to start building" }
        return model.hasStarted ? "Ask Claude for a change…" : "Describe the site you want to build…"
    }

    // MARK: Preview pane

    private var previewPane: some View {
        VStack(spacing: 0) {
            browserChrome
            ZStack {
                OPColor.surface
                if let url = model.previewURL {
                    PreviewWebView(url: url, reloadToken: model.reloadToken)
                } else if model.isRunning {
                    previewBooting
                } else {
                    previewEmpty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPColor.surface5)
    }

    private var browserChrome: some View {
        HStack(spacing: 9) {
            HStack(spacing: 2) {
                chromeGlyph("chevron.left")
                chromeGlyph("chevron.right")
            }
            Button { model.bumpPreview() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(OPColor.textMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!server.isServing)

            HStack(spacing: 8) {
                Circle().fill(server.isServing ? OPColor.serving : OPColor.textFainter).frame(width: 6, height: 6)
                Text(verbatim: server.isServing ? "localhost:\(server.port)" : "not serving")
                    .font(OPFont.mono(12))
                    .foregroundStyle(OPColor.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(OPColor.surface5, in: RoundedRectangle(cornerRadius: 8))

            Text("Local")
                .font(OPFont.mono(10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(OPColor.textFaint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.12)))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(OPColor.surface3)
        .overlay(alignment: .bottom) { Rectangle().fill(OPColor.hairline).frame(height: 1) }
    }

    private func chromeGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14))
            .foregroundStyle(OPColor.borderStrong)
            .frame(width: 24, height: 24)
    }

    private var previewBooting: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.small)
            Text("Starting server…")
                .font(OPFont.mono(12))
                .foregroundStyle(OPColor.textMuted)
        }
    }

    private var previewEmpty: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                Image("overprint-mark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .opacity(0.55)
                Text("Your site preview appears here")
                    .font(OPFont.ui(13))
                    .foregroundStyle(OPColor.textFaint)
            }
            .frame(width: 300, height: 172)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Color.black.opacity(0.18))
            )
            Text("Describe your site to start the server.")
                .font(OPFont.ui(12))
                .foregroundStyle(OPColor.textFainter)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
    }
}

// MARK: - Rows and chrome

private struct SuggestionChip: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(OPFont.mono(11))
                    .foregroundStyle(OPColor.textFainter)
                Text(label)
                    .font(OPFont.ui(13))
                    .foregroundStyle(OPColor.ink)
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? OPColor.surface4 : OPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = enabled && $0 }
    }
}

private struct StepRow: View {
    let step: BuildModel.Step

    var body: some View {
        HStack(spacing: 11) {
            statusIcon
            Text(step.label)
                .font(OPFont.ui(13))
                .foregroundStyle(step.status == .pending ? OPColor.textFaint : OPColor.ink)
            Spacer()
            if !step.detail.isEmpty {
                Text(step.detail)
                    .font(OPFont.mono(11))
                    .foregroundStyle(OPColor.textFainter)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var statusIcon: some View {
        switch step.status {
        case .done:
            ZStack {
                Circle().fill(OPColor.ink).frame(width: 16, height: 16)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
        case .active:
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
        case .pending:
            Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: 1.8).frame(width: 15, height: 15)
        case .failed:
            ZStack {
                Circle().fill(Color(hex: 0xD03A2E)).frame(width: 16, height: 16)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
        }
    }
}

/// A chat bubble with one squared-off corner, matching the prototype's asymmetric radii.
private struct BubbleShape: Shape {
    enum Tail { case topLeft, topRight, none }
    var tail: Tail

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 15
        let small: CGFloat = 4
        let (tl, tr, br, bl): (CGFloat, CGFloat, CGFloat, CGFloat)
        switch tail {
        case .topLeft: (tl, tr, br, bl) = (small, big, big, big)
        case .topRight: (tl, tr, br, bl) = (big, big, small, big)
        case .none: (tl, tr, br, bl) = (big, big, big, big)
        }
        return Path(roundedCorners: rect, topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }
}

private extension Path {
    init(roundedCorners rect: CGRect, topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
        self.init()
        move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        addArc(center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight), radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        addArc(center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight), radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        addArc(center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft), radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        addArc(center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft), radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        closeSubpath()
    }
}
