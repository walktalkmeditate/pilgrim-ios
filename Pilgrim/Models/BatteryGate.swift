import UIKit

/// The single low-battery gate for deferrable background work
/// (auto-transcription, Threads backfill). A negative level means the level
/// is unknown (e.g. simulator) and must not block work.
enum BatteryGate {

    @MainActor
    static func allowsBackgroundWork() -> Bool {
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let batteryState = device.batteryState
        device.isBatteryMonitoringEnabled = wasMonitoring
        return level < 0 || level > 0.2 || batteryState == .charging || batteryState == .full
    }
}
