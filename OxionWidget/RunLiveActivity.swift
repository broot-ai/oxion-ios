import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Пробежка / прогулка: экран блокировки и Dynamic Island с мини-картой маршрута.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OxionRunAttributes.self) { context in
            RunLockScreen(st: context.state)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(Color.oxLime)
                .widgetURL(URL(string: "oxion://run"))
        } dynamicIsland: { context in
            let st = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(st.kind == "walk" ? "Ходьба" : "Бег", systemImage: st.kind == "walk" ? "figure.walk" : "figure.run")
                            .font(.caption2.weight(.bold)).foregroundStyle(Color.oxLime)
                        RunTimer(st: st)
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        Text("\(st.km) км").font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MiniMap(points: st.points, paused: st.paused)
                        .frame(width: 92, height: 74)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack {
                            metric(st.pace, "темп /км", "speedometer", .white)
                            metric(st.heartRate.map(String.init) ?? "—", "пульс", "heart.fill", Color(red: 1, green: 0.3, blue: 0.38))
                            metric("\(st.calories)", "ккал", "flame.fill", Color(red: 1, green: 0.62, blue: 0.26))
                        }
                        RunButtons(st: st)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: st.kind == "walk" ? "figure.walk" : "figure.run")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.oxLime)
                    .padding(.leading, 4)
            } compactTrailing: {
                Text("\(st.km) км")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(st.paused ? .secondary : Color.white)
            } minimal: {
                Image(systemName: st.kind == "walk" ? "figure.walk" : "figure.run")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.oxLime)
            }
            .widgetURL(URL(string: "oxion://run"))
            .keylineTint(Color.oxLime)
        }
    }

    private func metric(_ v: String, _ t: String, _ icon: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(c)
                Text(v).font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
            }
            Text(t).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RunLockScreen: View {
    let st: OxionRunAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: st.kind == "walk" ? "figure.walk" : "figure.run").foregroundStyle(Color.oxLime)
                    RunTimer(st: st).font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    if st.paused { Text("пауза").font(.caption2.bold()).foregroundStyle(.secondary) }
                }
                HStack(spacing: 8) {
                    tile("\(st.km)", "км", "mappin.and.ellipse", Color.oxLime)
                    tile(st.pace, "/км", "speedometer", Color.oxSky)
                    tile(st.heartRate.map(String.init) ?? "—", "уд/мин", "heart.fill", Color(red: 1, green: 0.3, blue: 0.38))
                }
                RunButtons(st: st)
            }
            MiniMap(points: st.points, paused: st.paused)
                .frame(width: 104)
                .frame(maxHeight: .infinity)
        }
        .padding(14)
        .foregroundStyle(.white)
    }

    private func tile(_ v: String, _ u: String, _ icon: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(c)
            Text(v).font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(u).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct RunTimer: View {
    let st: OxionRunAttributes.ContentState
    var body: some View {
        if st.paused, let e = st.pausedElapsed {
            Text(e >= 3600 ? String(format: "%d:%02d:%02d", e / 3600, e / 60 % 60, e % 60) : String(format: "%d:%02d", e / 60, e % 60))
        } else {
            Text(timerInterval: st.timerStart...Date.distantFuture, countsDown: false)
        }
    }
}

struct RunButtons: View {
    let st: OxionRunAttributes.ContentState
    var body: some View {
        HStack(spacing: 6) {
            Button(intent: RunTogglePauseIntent()) {
                Label(st.paused ? "Продолжить" : "Пауза", systemImage: st.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .foregroundStyle(.black)
                    .background(Color.oxLime, in: Capsule())
            }
            .buttonStyle(.plain)
            Link(destination: URL(string: "oxion://run")!) {
                Label("Завершить", systemImage: "flag.checkered")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.white.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Мини-карта: тёмная «схема улиц» и линия маршрута с точкой старта и текущим положением
struct MiniMap: View {
    let points: [(Double, Double)]
    let paused: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let s = min(w, h)
            let ox = (w - s) / 2, oy = (h - s) / 2
            let pts = points.map { CGPoint(x: ox + $0.0 * s, y: oy + $0.1 * s) }
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.11, green: 0.12, blue: 0.13))
                // «кварталы»: детерминированная сетка улиц
                Path { p in
                    let seed = points.count
                    for i in 0..<7 {
                        let x = w * CGFloat((i * 37 + seed * 3) % 100) / 100
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + w * 0.12, y: h))
                        let y = h * CGFloat((i * 53 + seed * 7) % 100) / 100
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y - h * 0.08))
                    }
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 2.5)
                if pts.count >= 2 {
                    Path { p in p.addLines(pts) }
                        .stroke(Color.oxLime.opacity(0.35), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    Path { p in p.addLines(pts) }
                        .stroke(Color.oxLime, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    Circle().fill(.white).frame(width: 6, height: 6).position(pts[0])
                    Circle().fill(Color.oxLime).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.black, lineWidth: 2))
                        .position(pts[pts.count - 1])
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: "location.fill").foregroundStyle(Color.oxLime)
                        Text("ищем GPS").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(paused ? 0.6 : 1)
        }
    }
}
