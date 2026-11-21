import ActivityKit
import AlarmKit
import WidgetKit
import SwiftUI

/// Отсчёт будильника OXION (конец отдыха) на экране блокировки и в Dynamic Island.
/// AlarmKit требует такую живую карточку, если у будильника есть обратный отсчёт.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<OxAlarmMeta>.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2).foregroundStyle(Color.oxLime)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(context.state)).font(.headline)
                    Text("OXION").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                timer(context.state).font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.oxLime)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Отдых", systemImage: "timer").font(.headline).foregroundStyle(Color.oxLime).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state).font(.title2.bold().monospacedDigit()).foregroundStyle(Color.oxLime)
                        .frame(width: 80).padding(.trailing, 6)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Color.oxLime)
            } compactTrailing: {
                timer(context.state).font(.caption.bold().monospacedDigit()).foregroundStyle(Color.oxLime).frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Color.oxLime)
            }
            .keylineTint(Color.oxLime)
        }
    }

    private func title(_ s: AlarmPresentationState) -> String {
        switch s.mode {
        case .countdown: return "Отдых"
        case .paused: return "Отдых на паузе"
        default: return "Отдых окончен"
        }
    }

    @ViewBuilder
    private func timer(_ s: AlarmPresentationState) -> some View {
        switch s.mode {
        case .countdown(let c):
            Text(timerInterval: Date.now...max(Date.now, c.fireDate), countsDown: true)
        case .paused(let p):
            let left = max(0, p.totalCountdownDuration - p.previouslyElapsedDuration)
            Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
        default:
            Text("0:00")
        }
    }
}
