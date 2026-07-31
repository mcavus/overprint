import SwiftUI
import OverprintKit

/// The Posts sidebar: draft vs published styling, selection, and a new-post button.
struct PostsListView: View {
    @ObservedObject var model: WriteModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Posts")
                    .font(OPFont.mono(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(OPColor.textFaint)
                Spacer()
                Button { model.newPost() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15))
                        .foregroundStyle(OPColor.textSecondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("New post")
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(height: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(OPColor.hairline).frame(height: 1) }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.posts, id: \.sourceURL) { loaded in
                        PostRow(
                            loaded: loaded,
                            selected: loaded.sourceURL == model.selectedURL,
                            action: { model.select(loaded.sourceURL) },
                            onDelete: { model.deletePost(loaded.sourceURL) }
                        )
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 248)
        .background(OPColor.surface2)
        .overlay(alignment: .trailing) { Rectangle().fill(OPColor.hairline).frame(width: 1) }
    }
}

private struct PostRow: View {
    let loaded: LoadedPost
    let selected: Bool
    let action: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    private var draft: Bool { loaded.post.draft }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    dot
                    Text(loaded.post.title)
                        .font(OPFont.ui(13.5, weight: .semibold))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(dateText)
                        .font(OPFont.mono(11.5))
                        .foregroundStyle(OPColor.textFainter)
                    badge
                }
                .padding(.leading, 14)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .trailing) {
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(OPColor.textMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Move this post to the Trash")
                .padding(.trailing, 8)
            }
        }
        .contextMenu {
            Button("Move to Trash", role: .destructive, action: onDelete)
        }
    }

    private var background: Color {
        if selected { return OPColor.border2 }
        return hovering ? Color.black.opacity(0.045) : .clear
    }

    @ViewBuilder private var dot: some View {
        if draft {
            Circle().strokeBorder(Color(hex: 0xB0B0B6), lineWidth: 1.5).frame(width: 6, height: 6)
        } else {
            Circle().fill(OPColor.accent).frame(width: 6, height: 6)
        }
    }

    private var badge: some View {
        Text(draft ? "Draft" : "Published")
            .font(OPFont.mono(9.5, weight: .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(draft ? OPColor.textMuted : OPColor.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                if draft {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.14))
                } else {
                    RoundedRectangle(cornerRadius: 5).fill(OPColor.border)
                }
            }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: loaded.post.date)
    }
}
