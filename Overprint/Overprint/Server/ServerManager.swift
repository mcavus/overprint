import Foundation
import SwiftUI
import OverprintKit

/// Owns the local preview server (from OverprintKit) and publishes its state for the UI.
/// Serves an already-built `dist/`; building is driven by `WriteModel`.
@MainActor
final class ServerManager: ObservableObject {
    @Published private(set) var isServing = false
    @Published private(set) var port = 0

    private let server = PreviewServer()

    var url: URL? { server.url }

    @discardableResult
    func start(dist: URL, port requested: Int = 4321) -> Bool {
        do {
            port = try server.start(directory: dist, port: requested)
            isServing = true
            return true
        } catch {
            NSLog("Overprint: preview server failed to start: \(error.localizedDescription)")
            isServing = false
            port = 0
            return false
        }
    }

    func stop() {
        server.stop()
        isServing = false
        port = 0
    }
}
