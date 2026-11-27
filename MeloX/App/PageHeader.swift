import SwiftUI

/// The three actions behind the top-right trio (messages,
/// song recognition, account). Passed down from ContentView so
/// a tab root can render the trio as plain views in its own
/// one-line header instead of as toolbar items.
struct TopBarActions {
    let onMessagesTap: () -> Void
    let onRecognitionTap: () -> Void
    let onAccountTap: () -> Void
}

/// One-line page header: a large title on the left, the page's
/// buttons on the right, sharing a single row — the layout the
/// Search page already had (inline title + trio pill), but with
/// the title at the same large size as the other pages.
///
/// The background is the plain page background (`.background`),
/// NOT a frosted bar: at scroll-top the header is invisible
/// against the page (no white block), and when the content
/// scrolls under it the opaque background hides it cleanly.
struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background)
    }
}

/// The frosted capsule the top-right buttons sit in. Shared by
/// the trio pill and by the Library header's combined capsule
/// (trio + create / sort), so every page's buttons look the same.
struct HeaderPill<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 18) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

/// The account avatar image alone, for embedding in a pill.
struct HeaderAvatar: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let profile = library.profile {
            AsyncImage(url: profile.artworkURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .background(.quaternary, in: .circle)
            .clipShape(.circle)
        } else {
            Image(
                systemName: library.isLoggedIn
                    ? "person.crop.circle.fill"
                    : "person.crop.circle"
            )
        }
    }
}

/// The messages + recognition + avatar trio as plain views
/// (not toolbar items), in one capsule. The messages button
/// only appears when logged in, matching the old toolbar.
struct HeaderTrioButtons: View {
    @Environment(LibraryStore.self) private var library

    let actions: TopBarActions

    var body: some View {
        HeaderPill {
            HeaderTrioContent(actions: actions)
        }
        .foregroundStyle(.red)
    }
}

/// The trio's three buttons without the capsule, so the Library
/// header can put them in one combined capsule with the create
/// and sort buttons (they all shared one pill in the nav bar).
struct HeaderTrioContent: View {
    @Environment(LibraryStore.self) private var library

    let actions: TopBarActions

    var body: some View {
        Group {
            if library.isLoggedIn {
                Button(action: actions.onMessagesTap) {
                    Label(
                        "ui.messages.private.title",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .labelStyle(.iconOnly)
                }
                .accessibilityLabel("ui.messages.private.title")
                .accessibilityHint("ui.messages.private.open_hint")
            }

            Button(action: actions.onRecognitionTap) {
                Label("ui.recognition.title", systemImage: "waveform")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("ui.recognition.title")

            Button(action: actions.onAccountTap) {
                HeaderAvatar()
            }
            .accessibilityLabel(avatarAccessibilityLabel)
        }
    }

    private var avatarAccessibilityLabel: String {
        if let profile = library.profile {
            return profile.name
        }
        return L10n.string("ui.account.title")
    }
}
