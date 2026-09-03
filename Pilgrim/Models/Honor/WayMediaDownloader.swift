import Combine
import Foundation

/// Downloads a Way's voices and photos on a background URLSession so a
/// locked phone finishes the job. Delegate-based by necessity: background
/// sessions reject async and completion-handler task APIs. Task ids map to
/// (wayId, relative file); the delivered temp file is moved atomically.
@MainActor
final class WayMediaDownloader: NSObject, ObservableObject {

    static let shared = WayMediaDownloader(store: .shared, sessionIdentifier: "org.walktalkmeditate.pilgrim.ways")

    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var failures: [String: [String]] = [:]
    @Published private(set) var active: Set<String> = []
    /// Way ids whose download hit a full disk; the coordinator names the problem instead of offering a retry.
    @Published private(set) var diskFull: Set<String> = []
    var backgroundCompletionHandler: (() -> Void)?

    private let store: WayStore
    /// Injectable so a spec can resume real tasks against an unroutable host
    /// instead of the live one; production always gets `WayImporter.baseURL`.
    private let baseURL: URL
    private var session: URLSession!
    private var tasks: [Int: (wayId: String, relative: String, cap: Int)] = [:]
    private var pending: [String: Set<String>] = [:]
    private var retried: [String: Set<String>] = [:]
    /// File count per Way at the moment `download(_:)` was called: `finish`
    /// reads this instead of reloading the Way from disk on every completion.
    private var totals: [String: Int] = [:]

    init(store: WayStore, sessionIdentifier: String, baseURL: URL = WayImporter.baseURL) {
        self.store = store
        self.baseURL = baseURL
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        // delegateQueue: .main is why every `MainActor.assumeIsolated` below
        // is sound — callbacks are guaranteed to land on the main queue.
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    nonisolated static func mediaFiles(for way: Way) -> [String] {
        var seen: Set<String> = []
        var files: [String] = []
        for moment in way.moments {
            let media: WayMedia?
            switch moment.kind {
            case .voice(_, _, _, let m): media = m
            case .photo(let m): media = m
            default: media = nil
            }
            if case .file(let relative)? = media, !seen.contains(relative) {
                seen.insert(relative)
                files.append(relative)
            }
        }
        return files
    }

    nonisolated static func remoteURL(baseURL: URL = WayImporter.baseURL, shareId: String, relative: String) -> URL {
        baseURL.appendingPathComponent(shareId).appendingPathComponent(relative)
    }

    nonisolated static func byteCap(for relative: String) -> Int {
        relative.hasPrefix("audio/") ? 15 * 1024 * 1024 : 2 * 1024 * 1024
    }

    /// The sharing side ships at most 12 recordings and 20 photos, so a
    /// manifest declaring more never came from a walk page this app made.
    /// `WayImporter.maxEncounters` alone would let one share id pull 200
    /// files (3 GB at the audio cap) onto the disk; refusing the excess
    /// before anything is enqueued bounds that at 12x15 MB + 20x2 MB.
    static let maxAudioFilesPerWay = 12
    static let maxPhotoFilesPerWay = 20

    /// Splits the files to fetch into the ones within the per-kind ceilings
    /// and the ones beyond them, preserving manifest order so the same
    /// manifest always refuses the same files.
    private static func withinCeilings(_ files: [String]) -> (accepted: [String], refused: [String]) {
        var accepted: [String] = []
        var refused: [String] = []
        var audio = 0, photos = 0
        for relative in files {
            let isAudio = relative.hasPrefix("audio/")
            let room = isAudio ? audio < maxAudioFilesPerWay : photos < maxPhotoFilesPerWay
            guard room else { refused.append(relative); continue }
            if isAudio { audio += 1 } else { photos += 1 }
            accepted.append(relative)
        }
        return (accepted, refused)
    }

    /// What `WayImporter.way(from:shareId:now:)` writes into every `media:
    /// .file(...)`: an index of at most 5 digits under the matching folder.
    /// A prefix check alone can't be trusted here — see `entry(from:)`.
    nonisolated private static let mediaPathPattern = "\\A(?:audio/[0-9]{1,5}\\.m4a|photos/[0-9]{1,5}\\.jpg)\\z"

    /// A relaunch drops in-memory task bookkeeping, but the background
    /// session still redelivers a download that finished while the app was
    /// suspended: this rebuilds (wayId, relative) from the request URL the
    /// way it was constructed by `remoteURL`. `pathComponents` decodes a
    /// percent-encoded slash (`audio%2F..%2F..%2Fx.m4a`) into a single
    /// component whose *content* still starts with "audio/", so a prefix
    /// check alone would pass it through; matching the exact shape
    /// `remoteURL` emits closes that gap. The `..` component check stays as
    /// a second guard against the traversal segments that arrive unencoded.
    nonisolated static func entry(from url: URL) -> (wayId: String, relative: String)? {
        guard url.host == WayImporter.baseURL.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, !components.contains("..") else { return nil }
        let shareId = components[0]
        guard WayImporter.isShareId(shareId) else { return nil }
        let relative = components.dropFirst().joined(separator: "/")
        guard relative.range(of: mediaPathPattern, options: .regularExpression) != nil else { return nil }
        return (wayId: "share:\(shareId)", relative: relative)
    }

    func download(_ way: Way) {
        guard case .share(let shareId, _) = way.source else { return }
        // A second `gather` from a reopened overview must not double-enqueue
        // a Way that's already downloading.
        guard !active.contains(way.id) else { return }
        // The ceilings are applied to everything the Way declares, not just
        // the files still missing, so a partly-fetched hostile manifest can't
        // walk past them one `download` at a time.
        let (declared, refused) = Self.withinCeilings(Self.mediaFiles(for: way))
        let files = declared.filter { !FileManager.default.fileExists(atPath: store.mediaURL(for: way.id, relative: $0).path) }
        failures[way.id] = refused.isEmpty ? nil : refused
        diskFull.remove(way.id)
        guard !files.isEmpty else {
            progress[way.id] = 1
            totals[way.id] = nil
            return
        }
        active.insert(way.id)
        pending[way.id] = Set(files)
        totals[way.id] = declared.count
        // Seeded from what's already on disk, not 0, so progress is monotonic
        // across repeated `download()` calls for the same Way.
        progress[way.id] = 1 - Double(files.count) / Double(declared.count)
        for relative in files { enqueue(wayId: way.id, shareId: shareId, relative: relative) }
    }

    func retry(_ way: Way) {
        // A retry tapped while the last failure is still hopping to the main
        // actor would find the Way still `active` and silently do nothing.
        // Clearing the bookkeeping first makes the retry unconditional: the
        // in-flight `finish` then finds no entry of its own and returns.
        cancel(wayId: way.id)
        download(way)
    }

    func cancel(wayId: String) {
        let ids = Set(tasks.filter { $0.value.wayId == wayId }.keys)
        for id in ids { tasks.removeValue(forKey: id) }
        active.remove(wayId)
        diskFull.remove(wayId)
        pending[wayId] = nil
        progress[wayId] = nil
        totals[wayId] = nil
        failures[wayId] = nil
        retried[wayId] = nil
        // Cancel only what was claimed above: a task that shows up here
        // after the snapshot belongs to a `download()` issued after this
        // cancellation, not to it.
        session.getAllTasks { allTasks in
            MainActor.assumeIsolated {
                for task in allTasks where ids.contains(task.taskIdentifier) { task.cancel() }
            }
        }
    }

    /// For tests and other non-singleton instances to tear down their own
    /// background session; `shared` lives for the app's lifetime and never
    /// calls this.
    func invalidate() {
        session.invalidateAndCancel()
    }

    private func enqueue(wayId: String, shareId: String, relative: String) {
        let task = session.downloadTask(with: Self.remoteURL(baseURL: baseURL, shareId: shareId, relative: relative))
        tasks[task.taskIdentifier] = (wayId, relative, Self.byteCap(for: relative))
        task.resume()
    }

    private func finish(taskId: Int, success: Bool, retryable: Bool = true, diskFull: Bool = false) {
        // With the entry already gone — cancelled by `cancel(wayId:)`, or
        // never present because this task predates the current process —
        // there is nothing left to record.
        guard let entry = tasks.removeValue(forKey: taskId) else { return }
        if diskFull { self.diskFull.insert(entry.wayId) }
        if !success {
            if retryable {
                let shareId = store.load(id: entry.wayId).flatMap { way -> String? in
                    if case .share(let id, _) = way.source { return id } else { return nil }
                }
                if let shareId, !(retried[entry.wayId]?.contains(entry.relative) ?? false) {
                    retried[entry.wayId, default: []].insert(entry.relative)
                    enqueue(wayId: entry.wayId, shareId: shareId, relative: entry.relative)
                    return
                }
            }
            failures[entry.wayId, default: []].append(entry.relative)
        }
        pending[entry.wayId]?.remove(entry.relative)
        let total = Double(totals[entry.wayId] ?? 0)
        let left = Double(pending[entry.wayId]?.count ?? 0)
        progress[entry.wayId] = total > 0 ? 1 - left / total : 1
        if left == 0 {
            active.remove(entry.wayId)
            totals[entry.wayId] = nil
            retried[entry.wayId] = nil
        }
    }

    private enum MoveOutcome { case moved, diskFull, failed }

    /// Both steps report failure so a missing directory can't be mistaken
    /// for a failed move.
    nonisolated private static func move(from location: URL, to dest: URL) -> MoveOutcome {
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return isDiskFull(error) ? .diskFull : .failed
        }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            return .moved
        } catch {
            return isDiskFull(error) ? .diskFull : .failed
        }
    }

    /// A full disk can surface as a `URLError` on the transfer itself or as
    /// an `NSCocoaErrorDomain` write error on the eventual file operation
    /// (directly, or wrapped as the underlying error).
    nonisolated private static func isDiskFull(_ error: Error) -> Bool {
        if (error as? URLError)?.code == .cannotWriteToFile { return true }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError { return isDiskFull(underlying) }
        return false
    }
}

extension WayMediaDownloader: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns: resolve and move it
        // synchronously, still inside the isolated block that follows.
        let taskId = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
        let requestURL = downloadTask.originalRequest?.url
        MainActor.assumeIsolated {
            self.deliver(taskId: taskId, requestURL: requestURL, status: status, size: size, location: location)
        }
    }

    /// The delivery decision, lifted out of the delegate callback so a spec
    /// can drive it without fabricating a `URLSessionDownloadTask`.
    func deliver(taskId: Int, requestURL: URL?, status: Int, size: Int, location: URL) {
        let known = tasks[taskId]
        guard let target = known.map({ (wayId: $0.wayId, relative: $0.relative) })
            ?? requestURL.flatMap(Self.entry(from:)) else { return }
        // Nothing may land for a Way that is gone — deleted by the walker or
        // swept as expired — whether or not an in-memory entry still
        // remembers the transfer. `move` creates the folder it writes into,
        // so a delivery past this point would resurrect a directory no list
        // can see and no delete can reach. Drop the bookkeeping rather than
        // record a failure: the Way it would be recorded against no longer
        // exists.
        guard store.load(id: target.wayId) != nil else {
            tasks.removeValue(forKey: taskId)
            return
        }
        // A resumed transfer finishes as 206, not 200. A relaunch-derived
        // target carries no remembered byte cap, so it falls back to the cap
        // its folder implies — never to "uncapped".
        guard (200...299).contains(status),
              known.map({ size <= $0.cap }) ?? (size <= Self.byteCap(for: target.relative)) else {
            finish(taskId: taskId, success: false)
            return
        }
        let dest = store.mediaURL(for: target.wayId, relative: target.relative)
        switch Self.move(from: location, to: dest) {
        case .moved: finish(taskId: taskId, success: true)
        case .diskFull: finish(taskId: taskId, success: false, retryable: false, diskFull: true)
        case .failed: finish(taskId: taskId, success: false)
        }
    }

    /// The byte cap is enforced while the bytes arrive, not after: an oversized
    /// object is cancelled as soon as it crosses its cap.
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            guard let entry = self.tasks[downloadTask.taskIdentifier] else { return }
            if totalBytesWritten > Int64(entry.cap) { downloadTask.cancel() }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        let cancelled = (error as? URLError)?.code == .cancelled
        // Disk-full is reported here, mid-transfer, not only on the
        // same-volume rename in `didFinishDownloadingTo` — both paths exist
        // because either can be where the OS actually surfaces it.
        let diskFull = Self.isDiskFull(error)
        Task { @MainActor in self.finish(taskId: taskId, success: false, retryable: !cancelled && !diskFull, diskFull: diskFull) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}

#if DEBUG
extension WayMediaDownloader {

    /// Seeds the in-memory bookkeeping a live transfer would have created,
    /// so a spec can drive `deliver` without a real background session.
    func _test_registerTask(id: Int, wayId: String, relative: String) {
        tasks[id] = (wayId, relative, Self.byteCap(for: relative))
    }

    func _test_hasTask(id: Int) -> Bool { tasks[id] != nil }
}
#endif
