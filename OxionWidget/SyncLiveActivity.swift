import ActivityKit
import WidgetKit
import SwiftUI

/// «OXION — Синхронизация» в настоящем Dynamic Island
struct SyncLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OxionSyncAttributes.self) { context in
            HStack(spacing: 14) {
                SyncRing(done: context.state.done, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OXION").font(.headline.weight(.heavy))
                    Text(context.state.done ? context.state.doneText : context.state.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(context.state.done ? Color.oxLime : .secondary)
                }
                Spacer()
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .widgetURL(URL(string: "oxion://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SyncRing(done: context.state.done, size: 40).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OXION").font(.headline.weight(.heavy))
                        Text(context.state.done ? context.state.doneText : context.state.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(context.state.done ? Color.oxLime : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.done {
                        Text(timerInterval: context.state.started...context.state.started.addingTimeInterval(3600), countsDown: false)
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 44).padding(.trailing, 6)
                    }
                }
            } compactLeading: {
                Image("ox-logo-w").resizable().scaledToFit().frame(width: 14, height: 18).padding(.leading, 2)
            } compactTrailing: {
                SyncRing(done: context.state.done, size: 18, line: 2.5)
            } minimal: {
                SyncRing(done: context.state.done, size: 18, line: 2.5)
            }
            .keylineTint(Color.oxLime)
            .widgetURL(URL(string: "oxion://home"))
        }
    }
}

/// Кольцо загрузки: крутится системой (ProgressView), по готовности — замкнутое кольцо с галочкой
private struct SyncRing: View {
    let done: Bool
    var size: CGFloat
    var line: CGFloat = 3

    var body: some View {
        ZStack {
            if done {
                Circle().stroke(Color.oxLime, lineWidth: line)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(Color.oxLime)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.oxLime)
                    .scaleEffect(size / 22)
                if size > 30 {
                    Image("ox-logo-w").resizable().scaledToFit().frame(width: size * 0.32, height: size * 0.42)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
