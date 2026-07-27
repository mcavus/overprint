import Testing
import Foundation
@testable import OverprintKit

@Test func loadsConfig() throws {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).yml")
    try "title: Blog\nauthor: Ada\ndescription: d\nurl: https://x.dev\n".write(to: url, atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: url) }

    let config = try SiteConfig.load(from: url)
    #expect(config.title == "Blog")
    #expect(config.author == "Ada")
    #expect(config.description == "d")
    #expect(config.url == "https://x.dev")
}

@Test func minimalConfigUsesDefaults() throws {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).yml")
    try "title: Only Title\n".write(to: url, atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: url) }

    let config = try SiteConfig.load(from: url)
    #expect(config.title == "Only Title")
    #expect(config.author == "")
    #expect(config.url == nil)
}

@Test func missingConfigThrows() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).yml")
    #expect(throws: OverprintError.self) {
        _ = try SiteConfig.load(from: url)
    }
}
