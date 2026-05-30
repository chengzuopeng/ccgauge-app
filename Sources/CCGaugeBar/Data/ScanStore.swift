// ScanStore.swift - main-actor UI store backed by a background ScanEngine.

import Foundation
import SwiftUI

@MainActor
public final class ScanStore: ObservableObject {

    // MARK: published state

    @Published public private(set) var scan: ScanResult?
    @Published public private(set) var status: ScanStatus = .idle
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastSyncedAt: Date?

    public enum ScanStatus: Equatable {
        case idle
        case scanning
        case syncing
        case ready
        case error(String)
    }

    // MARK: internals

    private let engine = ScanEngine()
    private var watcher: FileWatcher?
    private var pollTimer: Timer?
    private var debounceTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var pendingChangedPaths = Set<String>()
    private var debouncingChangedPaths = Set<String>()
    private var debouncingNeedsFullScan = false
    private var needsFullIncrementalScan = false
    private var needsForceScan = false
    private var pendingShowStatus = false
    private var needsSnapshotRebuild = false
    private var snapshotWorkStartedAt: Date?
    private var snapshotSummaryParts: [String] = []
    /// Set of provider dirs currently watched. Used by reinstallWatcherIfDirsChanged
    /// to detect when ~/.claude/projects or ~/.codex/sessions appears after launch
    /// (first-time users who launch ccgauge-bar BEFORE running claude / codex).
    private var watchedDirs: Set<String> = []

    private static let rescanDebounceNs: UInt64 = 250_000_000
    private static let snapshotDebounceNs: UInt64 = 120_000_000
    /// Fast poll when no provider dirs exist yet — picks up first-launch
    /// "user just ran `claude` for the first time" within ~30s. Once dirs
    /// are present, FSEvents handles real-time updates and we drop to a
    /// generous 5-minute fallback poll for missed-event safety.
    private static let pollIntervalEmpty: TimeInterval = 30
    private static let pollIntervalReady: TimeInterval = 300

    nonisolated public init() {}

    public func start() {
        Task { @MainActor in await self.bootstrap() }
        // installFileWatcher pre-checks which dirs exist and installs the
        // poll timer with the correct cadence (fast when empty, slow when
        // ready). Avoid calling installPollTimer separately.
        installFileWatcher()
    }

    deinit {
        pollTimer?.invalidate()
        debounceTask?.cancel()
        drainTask?.cancel()
    }

    // MARK: public API

    public func scanNow(force: Bool = false) async {
        enqueueFullScan(force: force, showStatus: true)
        await drainTask?.value
    }

    public func anyProviderDirExists() -> Bool {
        let fm = FileManager.default
        for dir in ClaudeParser.dirs() + CodexParser.dirs() {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                return true
            }
        }
        return false
    }

    // MARK: scan orchestration

    private struct WorkRequest {
        let fullScan: Bool
        let force: Bool
        let paths: [String]
        let showStatus: Bool
    }

    private func bootstrap() async {
        status = .scanning
        lastError = nil
        await loadPersistedSnapshot()
        enqueueFullScan(force: false, showStatus: scan == nil)
        await drainTask?.value
    }

    private func loadPersistedSnapshot() async {
        if let update = await engine.loadPersistedSnapshot() {
            apply(update: update, updateTimestampWhenUnchanged: true)
        }
    }

    private func enqueueFullScan(force: Bool, showStatus: Bool) {
        if force {
            needsForceScan = true
        } else {
            needsFullIncrementalScan = true
        }
        pendingShowStatus = pendingShowStatus || showStatus
        startDrainIfNeeded()
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor [weak self] in
            await self?.drainPendingWork()
        }
    }

    private func drainPendingWork() async {
        while true {
            if let request = takePendingWork() {
                await perform(request)
                continue
            }

            if needsSnapshotRebuild {
                try? await Task.sleep(nanoseconds: Self.snapshotDebounceNs)
                if hasPendingWork { continue }
                await publishDirtySnapshot()
                continue
            }

            break
        }

        drainTask = nil
        if hasPendingWork || needsSnapshotRebuild {
            startDrainIfNeeded()
        }
    }

    private var hasPendingWork: Bool {
        needsForceScan || needsFullIncrementalScan || !pendingChangedPaths.isEmpty
    }

    private func takePendingWork() -> WorkRequest? {
        let force = needsForceScan
        let fullScan = force || needsFullIncrementalScan
        let paths = Array(pendingChangedPaths)
        let showStatus = pendingShowStatus

        guard fullScan || !paths.isEmpty else {
            pendingShowStatus = false
            return nil
        }

        needsForceScan = false
        needsFullIncrementalScan = false
        pendingChangedPaths.removeAll()
        pendingShowStatus = false

        return WorkRequest(fullScan: fullScan,
                           force: force,
                           paths: fullScan ? [] : paths,
                           showStatus: showStatus)
    }

    private func perform(_ request: WorkRequest) async {
        if request.showStatus {
            status = scan == nil ? .scanning : .syncing
            lastError = nil
        }

        if request.fullScan {
            await doScan(force: request.force, showStatus: request.showStatus)
        } else {
            await doReconcileCache(paths: request.paths)
        }
    }

    private func doScan(force: Bool, showStatus: Bool) async {
        do {
            let update = try await engine.scan(force: force)
            needsSnapshotRebuild = false
            snapshotWorkStartedAt = nil
            snapshotSummaryParts.removeAll()
            apply(update: update, updateTimestampWhenUnchanged: showStatus)
        } catch {
            lastError = "\(error)"
            status = .error("\(error)")
            PerfLog.logError("scan.error", error)
        }
    }

    private func doReconcileCache(paths: [String]) async {
        do {
            guard let update = try await engine.reconcileCache(paths: paths) else { return }
            guard update.changed else { return }
            markSnapshotDirty(update)
        } catch {
            lastError = "\(error)"
            status = .error("\(error)")
            PerfLog.logError("scan.reconcile.error", error)
        }
    }

    private func markSnapshotDirty(_ update: ReconcileCacheUpdate) {
        needsSnapshotRebuild = true
        if snapshotWorkStartedAt == nil {
            snapshotWorkStartedAt = update.started
        }
        snapshotSummaryParts.append(update.summary)
        if snapshotSummaryParts.count > 4 {
            snapshotSummaryParts.removeFirst(snapshotSummaryParts.count - 4)
        }
    }

    private func publishDirtySnapshot() async {
        guard needsSnapshotRebuild else { return }
        let started = snapshotWorkStartedAt ?? Date()
        let summary = snapshotSummaryParts.isEmpty
            ? "reconcile"
            : snapshotSummaryParts.joined(separator: "; ")

        needsSnapshotRebuild = false
        snapshotWorkStartedAt = nil
        snapshotSummaryParts.removeAll()

        let update = await engine.rebuildSnapshot(started: started, summary: summary)
        apply(update: update, updateTimestampWhenUnchanged: false)
    }

    private func apply(update: ScanUpdate, updateTimestampWhenUnchanged: Bool) {
        if update.changed || scan == nil {
            scan = update.result
            lastSyncedAt = Date()
            status = .ready
            PerfLog.log("scan.ready changed=true \(update.summary)")
        } else if updateTimestampWhenUnchanged {
            lastSyncedAt = Date()
            status = .ready
            PerfLog.log("scan.ready changed=false \(update.summary)")
        }
        // A scan may have discovered new provider dirs (e.g. user just
        // first-ran `claude` after launching ccgauge-bar with an empty
        // ~/.claude). If so, re-install the watcher to cover them and
        // relax the poll interval back to the slow path.
        reinstallWatcherIfDirsChanged()
    }

    // MARK: file watcher

    private func currentExistingDirs() -> Set<String> {
        let fm = FileManager.default
        var out: Set<String> = []
        for dir in ClaudeParser.dirs() + CodexParser.dirs() {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                out.insert(dir)
            }
        }
        return out
    }

    private func installFileWatcher() {
        let existing = currentExistingDirs()
        let dirs = Array(existing)
        watchedDirs = existing
        watcher?.stop()
        watcher = FileWatcher(dirs: dirs) { [weak self] paths in
            Task { @MainActor in self?.scheduleDebouncedRescan(paths: paths) }
        }
        watcher?.start()
        // Re-pace polling: if no dirs to watch, FSEvents can't help us
        // detect first-time creation → poll fast (30s) so we don't miss it.
        installPollTimer(empty: existing.isEmpty)
    }

    /// If the set of existing provider dirs has changed (new install / dir
    /// appeared after first claude run), tear down the watcher and install
    /// a fresh one covering the new set. Also re-paces the poll timer.
    private func reinstallWatcherIfDirsChanged() {
        let current = currentExistingDirs()
        guard current != watchedDirs else { return }
        PerfLog.log("watcher.reinstall old=\(watchedDirs.count) new=\(current.count)")
        installFileWatcher()
    }

    private func scheduleDebouncedRescan(paths: [String]) {
        let jsonlPaths = paths.filter { $0.hasSuffix(".jsonl") }
        if jsonlPaths.isEmpty {
            debouncingNeedsFullScan = true
        } else {
            debouncingChangedPaths.formUnion(jsonlPaths)
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.rescanDebounceNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.promoteDebouncedRescan()
            }
        }
    }

    private func promoteDebouncedRescan() {
        if debouncingNeedsFullScan {
            needsFullIncrementalScan = true
        } else {
            pendingChangedPaths.formUnion(debouncingChangedPaths)
        }
        debouncingNeedsFullScan = false
        debouncingChangedPaths.removeAll()
        startDrainIfNeeded()
    }

    private func installPollTimer(empty: Bool = false) {
        pollTimer?.invalidate()
        // FSEvents is the primary path. Polling exists for two reasons:
        //   (1) Catch FSEvents that the kernel may drop under load.
        //   (2) When no provider dir exists at launch, FSEvents has
        //       nothing to watch — polling is the only way we'll notice
        //       the user's first `claude` run.
        let interval = empty ? Self.pollIntervalEmpty : Self.pollIntervalReady
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.status != .scanning && self.status != .syncing else { return }
                self.enqueueFullScan(force: false, showStatus: false)
            }
        }
    }
}
