import SwiftUI

extension View {
    /// Apple Music-style one-line tab-root header: the page title
    /// sits on the same row as the trailing actions, vertically
    /// centred, instead of the two-row large-title layout (actions
    /// on top, huge title below). Detail pages are unaffected —
    /// they set their own title and display mode when pushed on top.
    @ViewBuilder
    func tabRootHeaderTitle(_ title: String) -> some View {
        navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(.title.bold())
                        .lineLimit(1)
                }
            }
    }

    /// Same one-line header, but the title is a menu (used by the
    /// library tab, where tapping the title switches the page).
    @ViewBuilder
    func tabRootHeaderTitleMenu<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        content()
                    } label: {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(.title.bold())
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
    }
}
