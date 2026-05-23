// FileWatcher.swift - recursive macOS FSEvents watcher for provider data dirs.

import Foundation
import CoreServices

public final class FileWatcher {
    public typealias OnChange = @Sendable ([String]) -> Void

    private let dirs: [String]
    private let onChange: OnChange
    private let queue = DispatchQueue(label: "dev.ccgauge.bar.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?

    /// Stable identity for the FSEventStream's `info` pointer. Holding a
    /// weak ref to the owner lets the stream outlive the FileWatcher
    /// briefly (e.g. during teardown) without dereferencing freed memory.
    private final class Box {
        weak var owner: FileWatcher?
        init(owner: FileWatcher) { self.owner = owner }
    }

    /// Strong reference so the box doesn't deallocate before we hand it to
    /// the stream's retain callback.
    private var box: Box?

    public init(dirs: [String], onChange: @escaping OnChange) {
        self.dirs = dirs
        self.onChange = onChange
    }

    public func start() {
        stop()

        let existingDirs = dirs.filter { dir in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
        }
        guard !existingDirs.isEmpty else { return }

        let newBox = Box(owner: self)
        self.box = newBox

        // FSEventStream uses retain/release on the `info` pointer to manage
        // its lifetime independently from ours. We pass +1 on the box up
        // front via `passRetained`; the retain callback adds further refs
        // for any internal copies; the release callback drops them. When
        // FSEventStreamRelease finally runs (from stop()), the box's last
        // ref drops cleanly.
        //
        // The callback then resolves Box.owner (weak) — if FileWatcher has
        // already been deallocated, owner is nil and the callback no-ops.
        // This eliminates the dangling-pointer race the prior
        // `passUnretained(self)` implementation had at teardown.
        let info = Unmanaged.passRetained(newBox).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: { ptr in
                guard let ptr else { return nil }
                _ = Unmanaged<Box>.fromOpaque(ptr).retain()
                return UnsafeRawPointer(ptr)
            },
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<Box>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            guard let watcher = box.owner else { return }
            let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self)
            let paths = (cfPaths as NSArray).compactMap { $0 as? String }
            watcher.onChange(paths)
        }

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existingDirs as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            // Create failed; balance the passRetained we did above so the
            // box doesn't leak.
            Unmanaged<Box>.fromOpaque(info).release()
            self.box = nil
            return
        }

        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
        stream = newStream
        PerfLog.log("watcher.started dirs=\(existingDirs.count)")
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        self.box = nil
    }

    deinit {
        stop()
    }
}
