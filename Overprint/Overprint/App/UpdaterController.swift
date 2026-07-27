import Foundation
import SwiftUI
import Sparkle

/// Wraps Sparkle so the app can check for and install its own updates.
///
/// Overprint is distributed as a signed, notarized DMG rather than through the App Store, so
/// updating is the app's own responsibility. Sparkle reads an appcast feed published alongside
/// each GitHub release, and verifies every download against `SUPublicEDKey` in Info.plist before
/// installing, so a compromised feed alone cannot ship code to users.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Whether the app is configured to update itself. False in local builds with no feed set.
    let isConfigured: Bool

    @Published var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let configured = (feed?.isEmpty == false)
        isConfigured = configured
        // Only start the updater when there is a feed. Starting it without one fails and Sparkle
        // reports "the updater failed to start", which is noise in every local build.
        controller = SPUStandardUpdaterController(
            startingUpdater: configured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecks = configured ? controller.updater.automaticallyChecksForUpdates : false
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        controller.updater.checkForUpdates()
    }

    /// False in builds with no feed, so the menu item is disabled rather than erroring.
    var canCheckForUpdates: Bool {
        isConfigured && controller.updater.canCheckForUpdates
    }

    var lastCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }
}
