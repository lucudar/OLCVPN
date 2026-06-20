import WidgetKit
import SwiftUI

// Виджет OLCVPN на главный экран. Намеренно простой и автономный:
// не зависит от App Group и сетевого расширения, поэтому собирается без
// дополнительных entitlement'ов. По нажатию открывается приложение.

struct OLCWidgetEntry: TimelineEntry {
    let date: Date
}

struct OLCProvider: TimelineProvider {
    func placeholder(in context: Context) -> OLCWidgetEntry {
        OLCWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (OLCWidgetEntry) -> Void) {
        completion(OLCWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OLCWidgetEntry>) -> Void) {
        completion(Timeline(entries: [OLCWidgetEntry(date: Date())], policy: .never))
    }
}

struct OLCWidgetEntryView: View {
    var entry: OLCProvider.Entry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.white)
            Text("OLCVPN")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Открыть")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground(Color(red: 0.06, green: 0.06, blue: 0.07))
    }
}

struct OLCWidget: Widget {
    let kind = "OLCWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OLCProvider()) { entry in
            OLCWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OLCVPN")
        .description("Быстрый доступ к OLCVPN.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OLCWidgetBundle: WidgetBundle {
    var body: some Widget {
        OLCWidget()
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}
