import Foundation

/// Deep link shared by the main app and the Lyrics widget.
///
/// Root cause of the Dynamic Island tap bug: the Live Activity widget
/// never set a `widgetURL`, the main app registered no URL scheme, and
/// nothing in the app handled an incoming URL or a Live Activity
/// `NSUserActivity`. Tapping the island therefore had nowhere to go.
///
/// The fix is the three pieces together — this file is only the shared
/// definition; the widget sets `widgetURL` to `nowPlayingURL`, the app
/// registers the `melox` scheme in `MeloX/Info.plist`, and `MeloXApp`
/// handles the URL (plus the system Live Activity user activity) and
/// asks `ContentView` to present the Now Playing screen.
nonisolated enum LyricsLiveActivityDeepLink {
    static let urlScheme = "melox"

    /// `melox://now-playing` — opens MeloX on the Now Playing screen.
    static let nowPlayingURL = URL(string: "melox://now-playing")!

    /// The `NSUserActivity` type the system delivers when a Live
    /// Activity is tapped without an explicit deep link.
    static let liveActivityUserActivityType = "NSUserActivityTypeLiveActivity"

    static func isNowPlaying(_ url: URL) -> Bool {
        guard url.scheme == urlScheme else { return false }
        // `melox://now-playing` has host "now-playing" and an empty path;
        // also accept `melox:///now-playing` for safety.
        return url.host == "now-playing" || url.path == "/now-playing"
    }
}
