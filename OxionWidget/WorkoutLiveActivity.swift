import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Тренировка в Dynamic Island и на экране блокировки.
/// Таймеры рисует сама система по меткам времени (Text(timerInterval:)) — приложение не обновляет их каждую секунду.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OxionWorkoutAttributes.self) { context in
            LockScreenWorkout(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.oxLime)
                .widgetURL(URL(string: "oxion://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image("ox-logo-w").resizable().scaledToFit().frame(width: 14, height: 18)
                            Text(phaseTitle(context.state, stale: context.isStale)).font(.caption2.bold()).foregroundStyle(Color.oxLime)
                        }
                        Text(context.state.exercise).font(.headline).lineLimit(1)
                        Text("Подход \(context.state.setIndex) из \(context.state.setsTotal)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        BigTimer(st: context.state, stale: context.isStale)
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(context.state.phase == "resting" ? Color.oxLime : .white)
                        Text(repsText(context.state)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.progress).tint(Color.oxLime)
                        HStack {
                            Text("Упр. \(context.state.exercisesDone)/\(context.state.exercisesTotal) · осталось подходов: \(context.state.setsLeft)")
                            Spacer()
                            if let n = context.state.nextExercise { Text("→ \(n)").lineLimit(1) }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Controls(st: context.state, stale: context.isStale, compact: true)
                    }
                }
            } compactLeading: {
                Image("ox-logo-w").resizable().scaledToFit().frame(width: 16, height: 20)
                    .padding(.leading, 2)
            } compactTrailing: {
                BigTimer(st: context.state, stale: context.isStale)
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(context.state.phase == "resting" ? Color.oxLime : .white)
                    .frame(maxWidth: 52)
            } minimal: {
                if context.state.phase == "resting", let end = context.state.restEnd, !context.isStale {
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true, showsHours: false)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.oxLime)
                        .frame(maxWidth: 36)
                } else {
                    Image("ox-logo-w").resizable().scaledToFit().frame(width: 14, height: 18)
                }
            }
            .widgetURL(URL(string: "oxion://workout"))
            .keylineTint(Color.oxLime)
        }
    }
}

// MARK: - Экран блокировки

struct LockScreenWorkout: View {
    let context: ActivityViewContext<OxionWorkoutAttributes>

    var body: some View {
        let st = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("ox-logo-w").resizable().scaledToFit().frame(width: 18, height: 23)
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.attributes.title).font(.caption.bold()).foregroundStyle(Color.oxLime).lineLimit(1)
                    Text(phaseTitle(st, stale: context.isStale)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                BigTimer(st: st, stale: context.isStale)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(st.phase == "resting" ? Color.oxLime : .white)
                    .multilineTextAlignment(.trailing)
            }
            if st.phase == "finished" {
                Text("Тренировка завершена · \(st.setsDoneAll) подходов").font(.headline)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(st.exercise).font(.title3.bold()).lineLimit(1)
                    Spacer()
                    Text("\(st.setIndex)/\(st.setsTotal)").font(.headline.monospacedDigit()).foregroundStyle(Color.oxLime)
                }
                HStack(spacing: 10) {
                    Label(repsText(st), systemImage: "repeat")
                    Label("осталось \(st.setsLeft)", systemImage: "square.stack.3d.up")
                    if let n = st.nextExercise { Label(n, systemImage: "arrow.turn.down.right").lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView(value: st.progress).tint(Color.oxLime)
                Controls(st: st, stale: context.isStale, compact: false)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

// MARK: - Общие элементы

/// Таймер: на отдыхе — обратный отсчёт до конца отдыха, иначе — время тренировки. На паузе — замершее значение.
struct BigTimer: View {
    let st: OxionWorkoutAttributes.ContentState
    let stale: Bool

    var body: some View {
        if st.phase == "paused" {
            Text(fmt(st.pausedRestLeft ?? st.pausedElapsed ?? 0))
        } else if st.phase == "resting", let end = st.restEnd, end > Date(), !stale {
            Text(timerInterval: Date()...end, countsDown: true, showsHours: false)
        } else if st.phase == "finished" {
            Image(systemName: "checkmark.circle.fill")
        } else if st.phase == "resting" {
            Text("0:00")
        } else {
            Text(timerInterval: st.timerStart...Date.distantFuture, countsDown: false)
        }
    }

    private func fmt(_ s: Int) -> String { String(format: "%ld:%02ld", s / 60, s % 60) }
}

/// Кнопки управления — работают через App Intents (iOS 17+), меняют состояние тренировки в приложении
struct Controls: View {
    let st: OxionWorkoutAttributes.ContentState
    let stale: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch st.phase {
            case "paused":
                btn(ResumeWorkoutIntent(), "Продолжить", "play.fill", primary: true)
                btn(FinishWorkoutIntent(), compact ? "Стоп" : "Завершить", "stop.fill", primary: false)
            case "resting":
                if stale || (st.restEnd ?? Date()) <= Date() {
                    btn(NextSetIntent(), "Следующий подход", "arrow.right", primary: true)
                } else {
                    btn(SkipRestIntent(), "Пропустить отдых", "forward.fill", primary: true)
                }
                btn(PauseWorkoutIntent(), "", "pause.fill", primary: false)
            case "finished":
                EmptyView()
            default:
                btn(CompleteSetIntent(), "Завершить подход", "checkmark", primary: true)
                btn(PauseWorkoutIntent(), "", "pause.fill", primary: false)
                if !compact { btn(FinishWorkoutIntent(), "", "stop.fill", primary: false) }
            }
        }
    }

    private func btn<I: AppIntent>(_ intent: I, _ title: String, _ icon: String, primary: Bool) -> some View {
        Button(intent: intent) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                if !title.isEmpty { Text(title).lineLimit(1) }
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: title.isEmpty ? 44 : .infinity, minHeight: 34)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(primary ? Color.oxLime : Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

func phaseTitle(_ st: OxionWorkoutAttributes.ContentState, stale: Bool) -> String {
    switch st.phase {
    case "resting": return stale || (st.restEnd ?? Date()) <= Date() ? "Отдых окончен" : "Отдых"
    case "paused": return "Пауза"
    case "finished": return "Готово"
    default: return "Выполнение"
    }
}

func repsText(_ st: OxionWorkoutAttributes.ContentState) -> String {
    var s = "\(st.reps) повт."
    if let w = st.weight, w > 0 {
        s += " · " + (w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)) + " \(st.unit)"
    }
    return s
}
