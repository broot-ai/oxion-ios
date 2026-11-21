import WidgetKit
import SwiftUI
import AppIntents

// Умные устройства: виджет на экран блокировки / «Домой» и кнопки в Пункте управления

struct DevicesEntry: TimelineEntry {
    let date: Date
    let snap: DeviceSnapshot
}

struct DevicesProvider: TimelineProvider {
    func placeholder(in context: Context) -> DevicesEntry {
        DevicesEntry(date: Date(), snap: DeviceSnapshot(devices: [.init(name: "Пульсометр", battery: 82, heart: true)], heartRate: 128, heartAt: Date()))
    }
    func getSnapshot(in context: Context, completion: @escaping (DevicesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : DevicesEntry(date: Date(), snap: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DevicesEntry>) -> Void) {
        let e = DevicesEntry(date: Date(), snap: .load())
        // через 2 минуты пульс «устаревает» — перерисуем без него
        completion(Timeline(entries: [e, DevicesEntry(date: Date().addingTimeInterval(125), snap: e.snap)], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

private let heartRed = Color(red: 1, green: 0.23, blue: 0.36)

struct DevicesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DevicesEntry

    var body: some View {
        let s = entry.snap
        switch family {
        case .accessoryCircular:
            if let hr = s.freshHeart {
                Gauge(value: Double(min(max(hr, 40), 200)), in: 40...200) {
                    Image(systemName: "heart.fill")
                } currentValueLabel: {
                    Text("\(hr)").font(.system(.title3, design: .rounded).bold())
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: s.devices.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                            .font(.title3)
                        Text("\(s.devices.count)").font(.caption2.bold())
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                    if let hr = s.freshHeart {
                        Text("\(hr)").font(.headline.monospacedDigit()) + Text(" уд/мин").font(.caption2)
                    } else {
                        Text("OXION · устройства").font(.headline)
                    }
                }
                .widgetAccentable()
                if s.devices.isEmpty {
                    Text("Нет подключённых").font(.caption)
                } else {
                    ForEach(s.devices.prefix(2), id: \.self) { d in
                        Text(d.name + (d.battery.map { " · \($0)%" } ?? "")).font(.caption).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            if let hr = s.freshHeart {
                Label("\(hr) уд/мин", systemImage: "heart.fill")
            } else {
                Label(s.devices.isEmpty ? "Устройства не подключены" : "Подключено: \(s.devices.count)", systemImage: "antenna.radiowaves.left.and.right")
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "heart.fill").foregroundStyle(heartRed)
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.secondary)
                }
                if let hr = s.freshHeart {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(hr)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("уд/мин").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Пульс").font(.title3.bold())
                }
                Spacer(minLength: 0)
                if s.devices.isEmpty {
                    Text("Нажмите, чтобы подключить").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(s.devices.prefix(2), id: \.self) { d in
                        HStack(spacing: 4) {
                            Circle().fill(Color.oxLime).frame(width: 6, height: 6)
                            Text(d.name).font(.caption).lineLimit(1)
                            Spacer(minLength: 0)
                            if let b = d.battery { Text("\(b)%").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}

struct DevicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DeviceSnapshot.widgetKind, provider: DevicesProvider()) { e in
            DevicesWidgetView(entry: e)
                .containerBackground(for: .widget) { Color.black }
                .widgetURL(URL(string: "oxion://devices"))
        }
        .configurationDisplayName("Умные устройства")
        .description("Пульс с датчика или часов и заряд подключённых устройств")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Пункт управления

struct HeartValueProvider: ControlValueProvider {
    var previewValue: Int { 0 }
    func currentValue() async throws -> Int { DeviceSnapshot.load().freshHeart ?? 0 }
}

struct HeartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: DeviceSnapshot.heartControlKind, provider: HeartValueProvider()) { bpm in
            ControlWidgetButton(action: OpenOxionIntent(route: "devices")) {
                Label(bpm > 0 ? "\(bpm) уд/мин" : "Пульс", systemImage: "heart.fill")
            }
        }
        .displayName("Пульс OXION")
        .description("Текущий пульс с датчика; нажмите — откроется панель устройств")
    }
}

struct DevicesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ru.oxion.app.control.devices") {
            ControlWidgetButton(action: OpenOxionIntent(route: "devices")) {
                Label("Устройства", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
        .displayName("Умные устройства")
        .description("Панель датчиков, часов и колонок OXION")
    }
}

struct Rest90Control: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ru.oxion.app.control.rest90") {
            ControlWidgetButton(action: OpenOxionIntent(route: "rest/90")) {
                Label("Отдых 90 с", systemImage: "timer")
            }
        }
        .displayName("Отдых 90 секунд")
        .description("Сразу ставит таймер отдыха на 90 секунд")
    }
}
