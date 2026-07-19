#if !APP_STORE
import AppKit
import Sparkle

// MARK: - Updater Manager

/// Owns the Sparkle auto-updater for direct-distribution (GitHub) builds.
/// App Store builds compile this out entirely; the App Store delivers
/// updates for those installs.
@MainActor
final class UpdaterManager {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Whether Sparkle checks for updates in the background. Persisted by
    /// Sparkle itself; setting it explicitly also suppresses Sparkle's
    /// first-run permission prompt.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
#endif
