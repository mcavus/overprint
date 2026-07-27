import Foundation

/// A site the user has opened before, shown in the launch window's Recents list.
struct RecentSite: Codable, Identifiable, Equatable {
    var path: String
    var name: String
    var lastOpened: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// Persists Recents and the "show launch window at startup" preference in UserDefaults.
final class RecentsStore {
    private let defaults: UserDefaults
    private let recentsKey = "recents.v1"
    private let showKey = "showLaunchAtStart"
    private let maxRecents = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: showKey) == nil {
            defaults.set(true, forKey: showKey)
        }
    }

    var showLaunchAtStart: Bool {
        get { defaults.bool(forKey: showKey) }
        set { defaults.set(newValue, forKey: showKey) }
    }

    func load() -> [RecentSite] {
        guard let data = defaults.data(forKey: recentsKey),
              let list = try? JSONDecoder().decode([RecentSite].self, from: data)
        else { return [] }
        // Drop entries whose folder has been moved or deleted. A recent that cannot open is a
        // dead end, so prune it and persist the result rather than failing on every click.
        let existing = list.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != list.count { save(existing) }
        return existing.sorted { $0.lastOpened > $1.lastOpened }
    }

    @discardableResult
    func record(url: URL, name: String) -> [RecentSite] {
        var list = load().filter { $0.path != url.path }
        let displayName = name.isEmpty ? url.lastPathComponent : name
        list.insert(RecentSite(path: url.path, name: displayName, lastOpened: Date()), at: 0)
        if list.count > maxRecents { list = Array(list.prefix(maxRecents)) }
        save(list)
        return list
    }

    @discardableResult
    func remove(path: String) -> [RecentSite] {
        let list = load().filter { $0.path != path }
        save(list)
        return list
    }

    @discardableResult
    func clear() -> [RecentSite] {
        save([])
        return []
    }

    private func save(_ list: [RecentSite]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: recentsKey)
        }
    }
}
