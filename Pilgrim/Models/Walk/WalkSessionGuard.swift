import Foundation
import UIKit
import CoreLocation
import Combine
import AVFoundation

class WalkSessionGuard {

    static weak var active: WalkSessionGuard?

    weak var builder: WalkBuilder?
    weak var locationManagement: LocationManagement?
    weak var viewModel: ActiveWalkViewModel?

    private var checkpointTimer: Timer?
    private var currentTier: PowerTier = .normal
    private var cancellables: [AnyCancellable] = []
    private var walkUUID: UUID?
    private var checkpointCount = 0

    private static let tag = "[SessionGuard]"

    // MARK: - Power Tiers

    enum PowerTier: Equatable, CustomStringConvertible {
        case normal
        case meditation
        case low
        case critical

        var checkpointInterval: TimeInterval {
            switch self {
            case .normal:     return 30
            case .meditation: return 60
            case .low:        return 15
            case .critical:   return 10
            }
        }

        var gpsAccuracy: CLLocationAccuracy {
            switch self {
            case .normal:     return kCLLocationAccuracyBest
            case .meditation: return 100
            case .low:        return kCLLocationAccuracyNearestTenMeters
            case .critical:   return kCLLocationAccuracyNearestTenMeters
            }
        }

        var distanceFilter: CLLocationDistance {
            switch self {
            case .normal:     return kCLDistanceFilterNone
            case .meditation: return 50
            case .low:        return 10
            case .critical:   return 10
            }
        }

        var description: String {
            switch self {
            case .normal:     return "normal"
            case .meditation: return "meditation"
            case .low:        return "low"
            case .critical:   return "critical"
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        Self.active = self

        let battery = UIDevice.current.batteryLevel
        let thermal = ProcessInfo.processInfo.thermalState
        print("\(Self.tag) START — battery: \(String(format: "%.0f%%", battery * 100)), thermal: \(Self.thermalName(thermal))")

        UIDevice.current.isBatteryMonitoringEnabled = true

        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in self?.recalculateTier() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in self?.recalculateTier() }
            .store(in: &cancellables)

        viewModel?.$isMeditating
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recalculateTier() }
            .store(in: &cancellables)

        recalculateTier()
        restartTimer()
    }

    func stopAndCleanup() {
        print("\(Self.tag) STOP — wrote \(checkpointCount) checkpoints during session")
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        cancellables.removeAll()
        locationManagement?.restoreDefaultPower()
        UIDevice.current.isBatteryMonitoringEnabled = false
        deleteCheckpointFile()
        Self.active = nil
    }

    deinit {
        checkpointTimer?.invalidate()
        print("\(Self.tag) DEINIT")
    }

    // MARK: - Checkpointing

    func checkpointNow() {
        guard let builder, let snapshot = builder.createCheckpointSnapshot() else {
            print("\(Self.tag) CHECKPOINT SKIPPED — no builder or no start date")
            return
        }

        if let viewModel {
            let intervals = viewModel.checkpointActivityIntervals()
            snapshot.replaceActivityIntervals(intervals)
        }

        if walkUUID == nil {
            walkUUID = Self.extractRecordingDirectoryUUID(from: snapshot) ?? UUID()
        }

        guard let resolvedUUID = walkUUID else { return }
        let checkpoint = WalkCheckpoint(walkUUID: resolvedUUID, walk: snapshot)

        do {
            let data = try JSONEncoder().encode(checkpoint)
            let url = Self.checkpointFileURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            checkpointCount += 1
            print("\(Self.tag) CHECKPOINT #\(checkpointCount) — tier: \(currentTier), routes: \(snapshot.routeData.count), pauses: \(snapshot.pauses.count), recordings: \(snapshot.voiceRecordings.count), intervals: \(snapshot.activityIntervals.count), size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        } catch {
            print("\(Self.tag) CHECKPOINT WRITE FAILED: \(error)")
        }
    }

    // MARK: - Tier Management

    private func recalculateTier() {
        let batteryLevel = UIDevice.current.batteryLevel
        let thermalState = ProcessInfo.processInfo.thermalState
        let isMeditating = viewModel?.isMeditating ?? false

        let newTier: PowerTier
        if (batteryLevel >= 0 && batteryLevel <= 0.05) || thermalState == .serious || thermalState == .critical {
            newTier = .critical
        } else if batteryLevel >= 0 && batteryLevel <= 0.20 {
            newTier = .low
        } else if isMeditating {
            newTier = .meditation
        } else {
            newTier = .normal
        }

        guard newTier != currentTier else { return }
        let oldTier = currentTier
        currentTier = newTier
        print("\(Self.tag) TIER \(oldTier) → \(newTier) — battery: \(String(format: "%.0f%%", batteryLevel * 100)), thermal: \(Self.thermalName(thermalState)), meditating: \(isMeditating), interval: \(newTier.checkpointInterval)s, gps: \(Self.accuracyName(newTier.gpsAccuracy))")
        applyTier(newTier)
    }

    private func applyTier(_ tier: PowerTier) {
        restartTimer()

        guard let locationManagement else { return }
        if tier == .normal {
            locationManagement.restoreDefaultPower()
        } else {
            locationManagement.adjustPower(accuracy: tier.gpsAccuracy, distanceFilter: tier.distanceFilter)
        }
    }

    private func restartTimer() {
        checkpointTimer?.invalidate()
        checkpointTimer = Timer.scheduledTimer(
            withTimeInterval: currentTier.checkpointInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkpointNow()
        }
    }

    // MARK: - File I/O

    static func checkpointFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("walk_checkpoint.json")
    }

    private func deleteCheckpointFile() {
        let url = Self.checkpointFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            print("\(Self.tag) CLEANUP — checkpoint file deleted")
        } catch {
            print("\(Self.tag) CLEANUP FAILED: \(error), retrying in 1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Recovery

    static func recoverIfNeeded(completion: @escaping (Date?) -> Void) {
        guard DataManager.dataStack != nil else {
            print("\(tag) RECOVERY SKIPPED — DataManager not ready")
            completion(nil)
            return
        }

        let url = checkpointFileURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("\(tag) RECOVERY — no checkpoint file found")
            completion(nil)
            return
        }

        print("\(tag) RECOVERY — checkpoint file found, decoding...")

        let checkpoint: WalkCheckpoint
        do {
            let data = try Data(contentsOf: url)
            checkpoint = try JSONDecoder().decode(WalkCheckpoint.self, from: data)
            print("\(tag) RECOVERY — decoded: schema=\(checkpoint.schemaVersion), walkUUID=\(checkpoint.walkUUID.uuidString.prefix(8))..., checkpointDate=\(checkpoint.checkpointDate)")
        } catch {
            print("\(tag) RECOVERY FAILED — decode error: \(error)")
            try? FileManager.default.removeItem(at: url)
            completion(nil)
            return
        }

        if DataManager.objectHasDuplicate(uuid: checkpoint.walkUUID, objectType: Walk.self) {
            print("\(tag) RECOVERY — stale checkpoint (walk already saved), deleting")
            try? FileManager.default.removeItem(at: url)
            completion(nil)
            return
        }

        let walk = checkpoint.walk
        let recordingDirUUID = extractRecordingDirectoryUUID(from: walk) ?? checkpoint.walkUUID
        reconnectOrphanedRecordings(walk: walk, walkUUID: recordingDirUUID)

        print("\(tag) RECOVERY — saving walk: start=\(walk.startDate), end=\(walk.endDate), routes=\(walk.routeData.count), pauses=\(walk.pauses.count), recordings=\(walk.voiceRecordings.count), intervals=\(walk.activityIntervals.count)")

        let recovered = NewWalk(
            workoutType: walk.workoutType,
            distance: walk.distance,
            steps: walk.steps,
            startDate: walk.startDate,
            endDate: walk.endDate,
            isRace: walk.isRace,
            comment: walk.comment,
            isUserModified: walk.isUserModified,
            finishedRecording: false,
            heartRates: walk._heartRates,
            routeData: walk._routeData,
            pauses: walk._pauses,
            workoutEvents: walk._workoutEvents,
            voiceRecordings: walk._voiceRecordings,
            activityIntervals: walk._activityIntervals
        )
        recovered.uuid = checkpoint.walkUUID

        DataManager.saveWalk(object: recovered) { success, error, _ in
            if success {
                try? FileManager.default.removeItem(at: url)
                print("\(tag) RECOVERY SUCCESS — walk from \(walk.startDate) saved, checkpoint deleted")
                completion(walk.startDate)
            } else {
                print("\(tag) RECOVERY SAVE FAILED: \(String(describing: error)), keeping checkpoint for retry")
                completion(nil)
            }
        }
    }

    private static func extractRecordingDirectoryUUID(from walk: TempWalk) -> UUID? {
        for recording in walk._voiceRecordings {
            let components = recording.fileRelativePath.split(separator: "/")
            if components.count >= 2, let dirUUID = UUID(uuidString: String(components[1])) {
                return dirUUID
            }
        }
        return nil
    }

    private static func reconnectOrphanedRecordings(walk: TempWalk, walkUUID: UUID) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings/\(walkUUID.uuidString)")

        guard FileManager.default.fileExists(atPath: recordingsDir.path) else {
            print("\(tag) ORPHAN SCAN — no recordings directory for \(walkUUID.uuidString.prefix(8))...")
            return
        }

        let existingPaths = Set(walk.voiceRecordings.map { $0.fileRelativePath })

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        var orphans: [TempVoiceRecording] = []

        for file in files where file.pathExtension == "m4a" {
            let relativePath = "Recordings/\(walkUUID.uuidString)/\(file.lastPathComponent)"
            guard !existingPaths.contains(relativePath) else { continue }

            let asset = AVURLAsset(url: file)
            let duration = CMTimeGetSeconds(asset.duration)
            guard duration > 0 else { continue }

            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let startDate = modDate.addingTimeInterval(-duration)

            let recording = TempVoiceRecording(
                uuid: UUID(),
                startDate: startDate,
                endDate: modDate,
                duration: duration,
                fileRelativePath: relativePath
            )
            orphans.append(recording)
            print("\(tag) ORPHAN FOUND — \(file.lastPathComponent), duration: \(String(format: "%.1f", duration))s")
        }

        if !orphans.isEmpty {
            walk.appendVoiceRecordings(orphans)
            print("\(tag) ORPHAN SCAN — reconnected \(orphans.count) recording(s)")
        }
    }

    // MARK: - Formatting Helpers

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func accuracyName(_ accuracy: CLLocationAccuracy) -> String {
        if accuracy == kCLLocationAccuracyBest { return "best" }
        if accuracy == kCLLocationAccuracyNearestTenMeters { return "10m" }
        return "\(Int(accuracy))m"
    }
}
