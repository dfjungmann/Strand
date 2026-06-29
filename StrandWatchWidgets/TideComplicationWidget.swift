import WidgetKit
import SwiftUI

struct TideComplicationEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
}

struct TideComplicationProvider: TimelineProvider {
    private let entryCount = 180

    func placeholder(in context: Context) -> TideComplicationEntry {
        TideComplicationEntry(date: .now, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TideComplicationEntry) -> Void) {
        Task {
            let events = await TideComplicationStore.loadEventsOrFetch()
            completion(TideComplicationEntry(date: .now, hasData: !events.isEmpty))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TideComplicationEntry>) -> Void) {
        Task {
            let events = await TideComplicationStore.loadEventsOrFetch()
            let hasData = !events.isEmpty
            let start = Date()
            var entries: [TideComplicationEntry] = []

            for offset in 0..<entryCount {
                let date = Calendar.current.date(byAdding: .minute, value: offset, to: start)!
                entries.append(TideComplicationEntry(date: date, hasData: hasData))
            }

            let refresh = Calendar.current.date(byAdding: .minute, value: entryCount, to: start)!
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }
}

struct TideComplicationEntryView: View {
    var entry: TideComplicationProvider.Entry
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var events: [TideEvent] {
        TideComplicationStore.loadEventsForDisplay()
    }

    var body: some View {
        TideComplicationDialView(
            now: entry.date,
            events: events,
            hasData: entry.hasData && !events.isEmpty
        )
        .containerBackground(for: .widget) {
            if renderingMode == .fullColor || renderingMode == .vibrant {
                Color(red: 0.82, green: 0.91, blue: 0.97)
            } else {
                AccessoryWidgetBackground()
            }
        }
    }
}

struct TideComplicationWidget: Widget {
    let kind = "TideComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TideComplicationProvider()) { entry in
            TideComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Strand Gezeiten")
        .description("Gezeiten-Uhr mit rotem Zeiger und Strandy-Bogen.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

@main
struct StrandWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TideComplicationWidget()
    }
}
