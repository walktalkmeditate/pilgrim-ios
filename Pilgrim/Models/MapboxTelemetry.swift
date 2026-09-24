import Foundation

/// Mapbox's SDK sends usage telemetry unless the app says otherwise; the
/// Android app already opts out, and a walk is nobody's usage metric.
enum MapboxTelemetry {

    /// The SDK registers `true` for this key and observes it, handing each
    /// change to Mapbox Common's events collection.
    static let metricsEnabledKey = "MGLMapboxMetricsEnabled"

    /// Written on every launch rather than once, so an opt-in left behind
    /// by the attribution sheet does not outlive the next start.
    static func optOut(_ defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: metricsEnabledKey)
    }
}
