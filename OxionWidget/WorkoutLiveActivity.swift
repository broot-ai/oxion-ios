import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Тренировка в Dynamic Island и на экране блокировки.
/// У каждого упражнения — фигура с подсвеченными мышцами. Отдых — кольцо, которое система анимирует сама
/// (ProgressView(timerInterval:)), без обновлений из приложения каждую секунду.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OxionWorkoutAttributes.self) { context in
            LockScreenWorkout(context: context)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(Color.oxLime)
                .widgetURL(URL(string: "oxion://workout"))
        } dynamicIsland: { context in
            let st = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 6) {
                        MuscleFigure(muscle: st.muscle, phase: st.phase)
                            .frame(width: 38, height: 62)
                    }
                    .padding(.leading, 6)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseRing(st: st, stale: context.isStale, size: 62, line: 6, big: 19)
                        .padding(.trailing, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(st.phase == "finished" ? "Готово!" : st.exercise)
                            .font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                        Text(subtitle(st, stale: context.isStale))
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                        SetDots(done: st.setIndex - 1, total: st.setsTotal, current: st.setIndex)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // только кнопки: высота развёрнутого острова ограничена, лишнее система обрезает
                    Controls(st: st, stale: context.isStale, compact: true)
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                }
            } compactLeading: {
                ZStack {
                    Circle().stroke(Color.oxLime.opacity(0.9), lineWidth: 2)
                    Image(systemName: st.phase == "resting" ? "hourglass" : "dumbbell.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.oxLime)
                }
                .frame(width: 22, height: 22)
                .padding(.leading, 2)
            } compactTrailing: {
                BigTimer(st: st, stale: context.isStale)
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(st.phase == "resting" ? Color.oxSky : .white)
                    .frame(maxWidth: 52)
            } minimal: {
                if st.phase == "resting", let end = st.restEnd, end > Date(), !context.isStale {
                    ProgressView(timerInterval: restStart(st)...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular)
                        .tint(Color.oxSky)
                } else {
                    Image(systemName: "dumbbell.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.oxLime)
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
            HStack(alignment: .center, spacing: 14) {
                MuscleFigure(muscle: st.muscle, phase: st.phase)
                    .frame(width: 50, height: 86)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image("ox-logo-w").resizable().scaledToFit().frame(width: 12, height: 15)
                        Text(context.attributes.title.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(Color.oxLime).lineLimit(1)
                    }
                    Text(st.phase == "finished" ? "Тренировка завершена" : st.exercise)
                        .font(.system(size: 19, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
                    if st.phase == "finished" {
                        Text("\(st.setsDoneAll) подходов").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(subtitle(st, stale: context.isStale)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        SetDots(done: st.setIndex - 1, total: st.setsTotal, current: st.setIndex)
                    }
                }
                Spacer(minLength: 4)
                PhaseRing(st: st, stale: context.isStale, size: 84, line: 8, big: 26)
            }
            if st.phase != "finished" {
                HStack(spacing: 8) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(Color.oxLime).frame(width: g.size.width * st.progress)
                            }
                        }
                    Text("\(st.setsDoneAll)/\(st.setsTotalAll)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    if let hr = st.heartRate { HeartBadge(hr: hr) }
                }
                Controls(st: st, stale: context.isStale, compact: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .foregroundStyle(.white)
    }
}

// MARK: - Элементы

extension Color {
    static let oxSky = Color(red: 0.35, green: 0.78, blue: 1.0)
}

private func subtitle(_ st: OxionWorkoutAttributes.ContentState, stale: Bool) -> String {
    var parts: [String] = []
    if let i = st.exerciseIndex { parts.append("Упр. \(i)/\(st.exercisesTotal)") }
    parts.append(repsText(st))
    if st.phase == "paused" { parts.insert("Пауза", at: 0) }
    return parts.joined(separator: " · ")
}

private func restStart(_ st: OxionWorkoutAttributes.ContentState) -> Date {
    guard let end = st.restEnd else { return Date() }
    let total = TimeInterval(max(1, st.restTotal ?? 90))
    return min(Date(), end.addingTimeInterval(-total))
}

/// Фигура с подсвеченной группой мышц (картинки в Assets виджета)
struct MuscleFigure: View {
    let muscle: String?
    let phase: String
    var body: some View {
        let key = ["chest", "back", "shoulders", "biceps", "triceps", "abs", "glutes", "legs", "cardio"].contains(muscle ?? "") ? muscle! : "none"
        Image("muscle-\(key)")
            .resizable()
            .scaledToFit()
            .opacity(phase == "paused" ? 0.5 : 1)
    }
}

/// Кружки подходов: выполненные — зелёные, текущий — с обводкой
struct SetDots: View {
    let done: Int
    let total: Int
    let current: Int
    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(1, min(total, 8)), id: \.self) { i in
                let isDone = i <= done
                let isCur = i == current && !isDone
                Text("\(i)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(isDone ? Color.black : .white.opacity(isCur ? 1 : 0.6))
                    .frame(width: 19, height: 19)
                    .background(isDone ? Color.oxLime : .clear, in: Circle())
                    .overlay(Circle().stroke(isDone ? .clear : Color.white.opacity(isCur ? 0.9 : 0.3), lineWidth: 1.2))
            }
            if total > 8 { Text("+\(total - 8)").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary) }
        }
    }
}

/// Кольцо: на отдыхе — обратный отсчёт, во время упражнения — прогресс всей тренировки и время
struct PhaseRing: View {
    let st: OxionWorkoutAttributes.ContentState
    let stale: Bool
    let size: CGFloat
    let line: CGFloat
    let big: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: line)
            if st.phase == "resting", let end = st.restEnd, end > Date(), !stale {
                ProgressView(timerInterval: restStart(st)...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(RingStyle(color: .oxSky, line: line))
                VStack(spacing: 0) {
                    Text(timerInterval: Date()...end, countsDown: true, showsHours: false)
                        .font(.system(size: big, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.oxSky)
                        .multilineTextAlignment(.center)
                    Text("отдых").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(width: size - line * 2.5)
            } else {
                Circle().trim(from: 0, to: max(0.02, st.phase == "finished" ? 1 : st.progress))
                    .stroke(Color.oxLime, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    BigTimer(st: st, stale: stale)
                        .font(.system(size: big * 0.68, weight: .bold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(st.phase == "resting" ? Color.oxLime : .white)
                    Text(st.phase == "paused" ? "пауза" : st.phase == "finished" ? "готово" : st.phase == "resting" ? "пора!" : "время")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(width: size - line * 2.5)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Кольцевой стиль для ProgressView с таймером (система сама анимирует значение)
struct RingStyle: ProgressViewStyle {
    let color: Color
    let line: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat(configuration.fractionCompleted ?? 0))
            .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

struct HeartBadge: View {
    let hr: Int
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill").foregroundStyle(Color(red: 1, green: 0.23, blue: 0.36))
            Text("\(hr)").monospacedDigit()
        }
        .font(.caption2.bold())
    }
}

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
            Image(systemName: "checkmark")
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
        HStack(spacing: 6) {
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
                btn(CompleteSetIntent(), "Подход сделан", "checkmark", primary: true)
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
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: title.isEmpty ? 40 : .infinity, minHeight: compact ? 28 : 32)
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
