import SwiftUI

/// Write mode: Posts sidebar, a header (file chip, Ask Claude pill, Edit/Preview toggle),
/// and the editor + live preview.
struct WriteView: View {
    @ObservedObject var model: WriteModel
    @ObservedObject var server: ServerManager
    @ObservedObject var ai: AIManager

    private enum Pane { case edit, preview }
    @State private var pane: Pane = .edit
    @State private var askOpen = false
    @AppStorage("pane.postsWidth") private var postsWidth: Double = PaneWidth.postsDefault

    private var previewURL: URL? {
        guard server.isServing, let base = server.url, let slug = model.selectedPost?.post.slug else { return nil }
        return base.appendingPathComponent("\(slug).html")
    }

    var body: some View {
        HSplitView {
            PostsListView(model: model)
                .frame(width: postsWidth)
                .frame(minWidth: PaneWidth.postsMin, maxWidth: PaneWidth.postsMax)
                // HSplitView reports the new width through the layout, not through a binding, so
                // read it back on change and persist it. Without this the drag is forgotten.
                .background(WidthReader { postsWidth = $0 })
            VStack(spacing: 0) {
                header
                editorAndPreview
            }
            .frame(minWidth: PaneWidth.editorMin + PaneWidth.previewMin, maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(OPColor.ink).frame(width: 6, height: 6)
                Text(model.selectedPost?.sourceURL.lastPathComponent ?? "No post")
                    .font(OPFont.mono(12.5))
                    .foregroundStyle(OPColor.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(OPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.1)))

            Button { askOpen.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(OPColor.accent)
                    Text("Ask Claude").font(OPFont.ui(12.5, weight: .medium)).foregroundStyle(Color(hex: 0x3A3A3E))
                }
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(askOpen ? OPColor.border2 : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $askOpen, arrowEdge: .bottom) {
                AskClaudePopover(ai: ai, model: model, isPresented: $askOpen)
            }

            if let error = model.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0xC0392B))
                    Text(error)
                        .font(OPFont.ui(11.5))
                        .foregroundStyle(Color(hex: 0x8A2A22))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Color(hex: 0xFDECEA), in: RoundedRectangle(cornerRadius: 6))
                .help(error)
            }

            Spacer()

            HStack(spacing: 2) {
                segButton("Edit", .edit)
                segButton("Preview", .preview)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(OPColor.border2))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(OPColor.surface3)
        .overlay(alignment: .bottom) { Rectangle().fill(OPColor.hairline).frame(height: 1) }
    }

    private func segButton(_ title: String, _ target: Pane) -> some View {
        Button { pane = target } label: {
            Text(title)
                .font(OPFont.ui(12.5, weight: pane == target ? .semibold : .medium))
                .foregroundStyle(pane == target ? OPColor.ink : Color(hex: 0x7A7A80))
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background {
                    if pane == target {
                        RoundedRectangle(cornerRadius: 6).fill(OPColor.surface)
                            .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var editorAndPreview: some View {
        if pane == .edit {
            HSplitView {
                MarkdownEditor(text: $model.editorText, onEdit: model.userDidEdit)
                    .frame(minWidth: PaneWidth.editorMin, maxWidth: .infinity, maxHeight: .infinity)
                previewPane
                    .frame(minWidth: PaneWidth.previewMin, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            previewPane.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var previewPane: some View {
        if let url = previewURL {
            PreviewWebView(url: url, reloadToken: model.reloadToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(OPColor.textFainter)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.18)))
                Text("Server stopped")
                    .font(OPFont.mono(12))
                    .foregroundStyle(OPColor.textFainter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPColor.surface)
        }
    }
}
