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
    private var session: URLSession!
    private var tasks: [Int: (wayId: String, relative: String, cap: Int)] = [:]
    private var pending: [String: Set<String>] = [:]
    private var retried: [String: Set<String>] = [:]
    /// File count per Way at the moment `download(_:)` was called: `finish`
    /// reads this instead of reloading the Way from disk on every completion.
    private var totals: [String: Int] = [:]

    init(store: WayStore, sessionIdentifier: String) {
        self.store = store
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

    nonisolated static func remoteURL(shareId: String, relative: String) -> URL {
        WayImporter.baseURL.appendingPathComponent(shareId).appendingPathComponent(relative)
    }

    nonisolated static func byteCap(for relative: String) -> Int {
        relative.hasPrefix("audio/") ? 15 * 1024 * 1024 : 2 * 1024 * 1024
    }

    /// A relaunch drops in-memory task bookkeeping, but the background
    /// session still redelivers a download that finished while the app was
    /// suspended: this rebuilds (wayId, relative) from the request URL the
    /// way it was constructed by `remoteURL`, refusing anything that
    /// doesn't already have the exact shape that call site produces.
    nonisolated static func entry(from url: URL) -> (wayId: String, relative: String)? {
        guard url.host == WayImporter.baseURL.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, !components.contains("..") else { return nil }
        let shareId = components[0]
        guard WayImporter.isShareId(shareId) else { return nil }
        let relative = components.dropFirst().joined(separator: "/")
        guard relative.hasPrefix("audio/") || relative.hasPrefix("photos/") else { return nil }
        return (wayId: "share:\(shareId)", relative: relative)
    }

    func download(_ way: Way) {
        guard case .share(let shareId, _) = way.source else { return }
        // A second `gather` from a reopened overview must not double-enqueue
        // a Way that's already downloading.
        guard !active.contains(way.id) else { return }
        let allFiles = Self.mediaFiles(for: way)
        let files = allFiles.filter { !FileManager.default.fileExists(atPath: store.mediaURL(for: way.id, relative: $0).path) }
        failures[way.id] = nil
        diskFull.remove(way.id)
        guard !files.isEmpty else {
            progress[way.id] = 1
            totals[way.id] = nil
            return
        }
        active.insert(way.id)
        pending[way.id] = Set(files)
        totals[way.id] = allFiles.count
        // Seeded from what's already on disk, not 0, so progress is monotonic
        // across repeated `download()` calls for the same Way.
        progress[way.id] = 1 - Double(files.count) / Double(allFiles.count)
        for relative in files { enqueue(wayId: way.id, shareId: shareId, relative: relative) }
    }

    func retry(_ way: Way) {
        retried[way.id] = nil
        diskFull.remove(way.id)
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

    private func enqueue(wayId: String, shareId: String, relative: String) {
        let task = session.downloadTask(with: Self.remoteURL(shareId: shareId, relative: relative))
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

    /// `createDirectory` used to be `try?`-swallowed, silently falling
    /// through to `moveItem` against a directory that might not exist; both
    /// steps now report failure instead of proceeding blind.
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
        MainActor.assumeIsolated {
            let known = self.tasks[taskId]
            guard let target = known.map({ (wayId: $0.wayId, relative: $0.relative) })
                ?? (downloadTask.originalRequest?.url).flatMap(Self.entry(from:)) else { return }
            // A resumed transfer finishes as 206, not 200; a relaunch-derived
            // target carries no remembered byte cap, so only an in-memory
            // entry can be checked against one.
            guard (200...299).contains(status), known.map({ size <= $0.cap }) ?? true else {
                self.finish(taskId: taskId, success: false)
                return
            }
            let dest = self.store.mediaURL(for: target.wayId, relative: target.relative)
            switch Self.move(from: location, to: dest) {
            case .moved: self.finish(taskId: taskId, success: true)
            case .diskFull: self.finish(taskId: taskId, success: false, diskFull: true)
            case .failed: self.finish(taskId: taskId, success: false)
            }
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
