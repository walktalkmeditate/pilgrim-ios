//
//  PilgrimHomeWidget.swift
//
//  Home Screen widget for Pilgrim.
//
//  Exists to satisfy Apple App Store review (Guideline 2.1(a)):
//  the Widget Extension target must provide at least one entry in
//  the Home Screen widget gallery, otherwise "Add Widget" flow has
//  no Pilgrim option and the app is flagged as incomplete.
//
//  Beyond unblocking review, this is a quiet piece of daily presence
//  — a short walking mantra that rotates once per day, matching the
//  app's wabi-sabi aesthetic. No data sharing required, no App Group,
//  no CoreStore dependency.
//
//  Pilgrim
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import WidgetKit
import SwiftUI

struct PilgrimHomeWidget: Widget {

    let kind: String = "PilgrimHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PilgrimHomeProvider()) { entry in
            PilgrimHomeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Self.parchment
                }
        }
        .configurationDisplayName("Pilgrim")
        .description("A quiet mantra for your walk.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    // MARK: - Adaptive colors
    //
    // The widget can appear on any wallpaper / in any color scheme, so
    // these need to adapt between light and dark mode. Values match
    // the main app's parchment / ink / fog asset catalog entries; kept
    // inline because the widget extension doesn't share an asset catalog
    // with the iOS target.

    static let parchment = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.110, green: 0.098, blue: 0.078, alpha: 1.0)
            : UIColor(red: 0.961, green: 0.945, blue: 0.914, alpha: 1.0)
    })

    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.941, green: 0.922, blue: 0.882, alpha: 1.0)
            : UIColor(red: 0.110, green: 0.098, blue: 0.078, alpha: 1.0)
    })

    static let fog = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.580, green: 0.557, blue: 0.533, alpha: 1.0)
            : UIColor(red: 0.420, green: 0.388, blue: 0.349, alpha: 1.0)
    })
}

// MARK: - Entry

struct PilgrimHomeEntry: TimelineEntry {
    let date: Date
    let phrase: String
}

// MARK: - Timeline Provider

struct PilgrimHomeProvider: TimelineProvider {

    /// Rotating mantras, one per day, indexed by day-of-year. Keeps the
    /// widget feeling alive without requiring any shared data access.
    /// Short enough to fit in a small widget without truncation.
    private static let phrases = [
        "Walk well.",
        "Every step is enough.",
        "Begin where you are.",
        "Slow is a speed.",
        "Breathe with your feet.",
        "Presence, step by step.",
        "The path is the way.",
        "Nowhere to arrive.",
        "Solvitur ambulando.",
        "One step is plenty."
    ]

    static func phrase(for date: Date) -> String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return phrases[dayOfYear % phrases.count]
    }

    func placeholder(in context: Context) -> PilgrimHomeEntry {
        PilgrimHomeEntry(date: Date(), phrase: "Walk well.")
    }

    func getSnapshot(in context: Context, completion: @escaping (PilgrimHomeEntry) -> Void) {
        let now = Date()
        completion(PilgrimHomeEntry(date: now, phrase: Self.phrase(for: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PilgrimHomeEntry>) -> Void) {
        // Emit one entry per day at local midnight, seven days ahead.
        // System schedules view updates at the entry boundaries. Policy
        // .after(endOfWeek) tells WidgetKit to request a fresh timeline
        // when the week runs out, so the mantra cycle continues.
        let calendar = Calendar.current
        var entries: [PilgrimHomeEntry] = []
        let startOfToday = calendar.startOfDay(for: Date())
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
                continue
            }
            entries.append(PilgrimHomeEntry(date: date, phrase: Self.phrase(for: date)))
        }
        let refreshDate = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? Date().addingTimeInterval(7 * 86400)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }
}

// MARK: - View

struct PilgrimHomeWidgetView: View {

    let entry: PilgrimHomeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(spacing: family == .systemMedium ? 12 : 10) {
            Image(systemName: "figure.walk")
                .font(.system(size: family == .systemMedium ? 32 : 26, weight: .light))
                .foregroundColor(PilgrimHomeWidget.ink)

            Text(entry.phrase)
                .font(.system(family == .systemMedium ? .callout : .caption, design: .serif))
                .italic()
                .foregroundColor(PilgrimHomeWidget.fog)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
