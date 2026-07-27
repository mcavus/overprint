import Foundation

/// Watches directories with FSEvents and fires a debounced callback on any change. Used to
/// live-reload the preview when files change on disk, including edits made outside the app.
final class FileWatcher {
    private let paths: [String]
    private let debounce: TimeInterval
    private let onChange: () -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.mcavus.Overprint.filewatcher")
    private var pending: DispatchWorkItem?

    /// `onChange` is invoked on `queue`; hop to the main actor inside it if touching UI.
    init(paths: [URL], debounce: TimeInterval = 0.25, onChange: @escaping () -> Void) {
        self.paths = paths.map(\.path)
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().fired()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func fired() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit { stop() }
}
