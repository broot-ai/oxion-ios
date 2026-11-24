import SwiftUI
import GameKit

// Медали достижений: картинки медалей, серии бронза → серебро → сапфир → золото.
// Полученные — яркие, ещё не полученные — серые с прогрессом. Выполненные отправляются в Game Center.

struct MedalsView: View {
    @State private var data: AchievementsResponse?
    @State private var error: String?
    @State private var open: Achievement?

    private var groups: [(String, [Achievement])] {
        var order: [String] = []
        var map: [String: [Achievement]] = [:]
        for a in data?.items ?? [] {
            let g = a.group ?? "Другое"
            if map[g] == nil { order.append(g) }
            map[g, default: []].append(a)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            if let d = data {
                VStack(spacing: 18) {
                    HStack(spacing: 14) {
                        Image("medal-cup-gold").resizable().scaledToFit().frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(d.done ?? 0) из \(d.total ?? 0)").font(.title2.bold())
                            Text("медалей получено").font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: Double(d.done ?? 0), total: Double(max(1, d.total ?? 1))).tint(Color.lime)
                        }
                    }
                    .padding(16)
                    .oxCardBG(22)

                    ForEach(groups, id: \.0) { g, items in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(g.uppercased()).font(.caption.bold()).foregroundStyle(.secondary).padding(.leading, 4)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                                ForEach(items) { a in
                                    Button { open = a } label: { MedalCell(a: a) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            } else {
                LoadingOrError(error: error) { Task { await load() } }
            }
        }
        .background(Color.oxBg)
        .navigationTitle("Медали")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $open) { MedalDetail(a: $0) }
    }

    private func load() async {
        do {
            let d: AchievementsResponse = try await API.call("/achievements")
            data = d
            error = nil
            reportToGameCenter(d.items)
        } catch { self.error = error.localizedDescription }
    }

    /// Game Center: работает, когда достижения заведены в App Store Connect (нужен платный аккаунт разработчика)
    private func reportToGameCenter(_ items: [Achievement]) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let list = items.map { a -> GKAchievement in
            let g = GKAchievement(identifier: "oxion." + a.key)
            g.percentComplete = Double(min(100, a.pct ?? 0))
            g.showsCompletionBanner = true
            return g
        }
        Task { try? await GKAchievement.report(list) }
    }
}

struct MedalCell: View {
    let a: Achievement
    var body: some View {
        VStack(spacing: 6) {
            MedalImage(a: a, size: 70)
            Text(a.title.components(separatedBy: " · ").last ?? a.title)
                .font(.caption2.bold())
                .lineLimit(1)
                .foregroundStyle(a.done ? .primary : .secondary)
            if !a.done {
                ProgressView(value: Double(a.pct ?? 0), total: 100)
                    .tint(Color.lime)
                    .frame(width: 50)
            }
        }
    }
}

struct MedalImage: View {
    let a: Achievement
    var size: CGFloat
    var body: some View {
        Group {
            if let m = a.medal, UIImage(named: m) != nil {
                Image(m).resizable().scaledToFit()
            } else {
                Text(a.icon).font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
        .saturation(a.done ? 1 : 0)
        .opacity(a.done ? 1 : 0.35)
        .shadow(color: a.done ? Color(hex: 0xFFB000).opacity(0.3) : .clear, radius: a.done ? 8 : 0)
        .overlay(alignment: .bottomTrailing) {
            if !a.done {
                Image(systemName: "lock.fill").font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5).background(.black.opacity(0.55), in: Circle())
            }
        }
    }
}

private struct MedalDetail: View {
    let a: Achievement
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            MedalImage(a: a, size: 170).padding(.top, 26)
            Text(a.title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(a.desc ?? "").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if a.done {
                Label("Получена", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Color.lime)
            } else {
                VStack(spacing: 6) {
                    ProgressView(value: Double(a.pct ?? 0), total: 100).tint(Color.lime)
                    Text("\(Int(a.value ?? 0)) из \(Int(a.need ?? 0))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }
            Button { dismiss() } label: { Text("Готово").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                .controlSize(.large)
                .padding(16)
        }
        .frame(maxWidth: .infinity)
        .background(Color.oxBg)
        .fitSheet()
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
    }
}
