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
    private var tasks: [Int: (wayId: String, relative: String, expected: Int)] = [:]
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
        relative.hasPrefix("photos/") ? 2 * 1024 * 1024 : 15 * 1024 * 1024
    }

    func download(_ way: Way) {
        guard case .share(let shareId, _) = way.source else { return }
        let files = Self.mediaFiles(for: way).filter {
            !FileManager.default.fileExists(atPath: store.mediaURL(for: way.id, relative: $0).path)
        }
        failures[way.id] = nil
        totals[way.id] = Self.mediaFiles(for: way).count
        guard !files.isEmpty else { progress[way.id] = 1; return }
        active.insert(way.id)
        pending[way.id] = Set(files)
        progress[way.id] = 0
        for relative in files { enqueue(wayId: way.id, shareId: shareId, relative: relative) }
    }

    func retry(_ way: Way) {
        retried[way.id] = nil
        download(way)
    }

    func cancel(wayId: String) {
        session.getAllTasks { tasks in
            MainActor.assumeIsolated {
                for task in tasks where self.tasks[task.taskIdentifier]?.wayId == wayId { task.cancel() }
            }
        }
        active.remove(wayId)
        pending[wayId] = nil
        progress[wayId] = nil
        totals[wayId] = nil
    }

    private func enqueue(wayId: String, shareId: String, relative: String) {
        let task = session.downloadTask(with: Self.remoteURL(shareId: shareId, relative: relative))
        tasks[task.taskIdentifier] = (wayId, relative, Self.byteCap(for: relative))
        task.resume()
    }

    private func finish(taskId: Int, success: Bool, retryable: Bool = true) {
        guard let entry = tasks.removeValue(forKey: taskId) else { return }
        if !success, retryable {
            let shareId = store.load(id: entry.wayId).flatMap { way -> String? in
                if case .share(let id, _) = way.source { return id } else { return nil }
            }
            if let shareId, !(retried[entry.wayId]?.contains(entry.relative) ?? false) {
                retried[entry.wayId, default: []].insert(entry.relative)
                enqueue(wayId: entry.wayId, shareId: shareId, relative: entry.relative)
                return
            }
            failures[entry.wayId, default: []].append(entry.relative)
        } else if !success {
            failures[entry.wayId, default: []].append(entry.relative)
        }
        pending[entry.wayId]?.remove(entry.relative)
        let total = Double(totals[entry.wayId] ?? 0)
        let left = Double(pending[entry.wayId]?.count ?? 0)
        progress[entry.wayId] = total > 0 ? 1 - left / total : 1
        if left == 0 {
            active.remove(entry.wayId)
            totals[entry.wayId] = nil
        }
    }
}

extension WayMediaDownloader: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns: move it synchronously, then hop to main for bookkeeping.
        let taskId = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
        let moved = MainActor.assumeIsolated { () -> Bool in
            guard let entry = self.tasks[taskId], status == 200, size <= entry.expected else { return false }
            let dest = self.store.mediaURL(for: entry.wayId, relative: entry.relative)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: location, to: dest)
                return true
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
                self.diskFull.insert(entry.wayId)
                return false
            } catch {
                return false
            }
        }
        Task { @MainActor in self.finish(taskId: taskId, success: moved) }
    }

    /// The byte cap is enforced while the bytes arrive, not after: an oversized
    /// object is cancelled as soon as it crosses its cap.
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            guard let entry = self.tasks[downloadTask.taskIdentifier] else { return }
            if totalBytesWritten > Int64(entry.expected) { downloadTask.cancel() }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        let cancelled = (error as? URLError)?.code == .cancelled
        Task { @MainActor in self.finish(taskId: taskId, success: false, retryable: !cancelled) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
