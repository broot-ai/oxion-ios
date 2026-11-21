import SwiftUI
import UIKit

// MARK: - Настройки оформления (как в Telegram): размер текста, углы сообщений, анимации, иконка

enum Look {
    static let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
    static let chatPoints: [CGFloat] = [13, 14, 15, 16, 18, 20, 23]
    static let names = ["Очень мелкий", "Мелкий", "Уменьшенный", "Обычный", "Крупный", "Очень крупный", "Огромный"]
}

/// Размер текста во всём приложении
struct AppTextSize: ViewModifier {
    @AppStorage("text_system") private var system = true
    @AppStorage("text_size") private var index = 3

    func body(content: Content) -> some View {
        if system {
            content.dynamicTypeSize(...DynamicTypeSize.large)
        } else {
            content.dynamicTypeSize(Look.sizes[min(max(index, 0), Look.sizes.count - 1)])
        }
    }
}

/// Параметры пузыря сообщения
struct BubbleStyle: DynamicProperty {
    @AppStorage("text_system") var system = true
    @AppStorage("text_size") var index = 3
    @AppStorage("bubble_radius") var radius: Double = 20

    var fontSize: CGFloat { system ? 16 : Look.chatPoints[min(max(index, 0), 6)] }
    var tail: CGFloat { min(6, radius) }
}

// MARK: экран «Оформление»

struct AppearanceSettingsView: View {
    @AppStorage("text_system") private var system = true
    @AppStorage("text_size") private var index = 3
    @State private var textSheet = false

    var body: some View {
        List {
            Section {
                Button { textSheet = true } label: {
                    LabeledContent("Размер текста", value: system ? "Системный" : Look.names[index])
                }
                .tint(.primary)
                NavigationLink("Углы блоков с сообщениями") { BubbleCornersView() }
                NavigationLink("Анимации") { AnimationSettingsView() }
            }
            Section("Иконка приложения") {
                AppIconPicker()
                    .listRowInsets(EdgeInsets(top: 14, leading: 10, bottom: 14, trailing: 10))
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $textSheet) { TextSizeSheet() }
    }
}

// MARK: предпросмотр чата

struct ChatPreview: View {
    var fontSize: CGFloat
    var radius: CGFloat

    private struct Msg: Identifiable { let id: Int; let mine: Bool; let text: String; var reply: String? = nil; var voice = false }
    private let msgs: [Msg] = [
        .init(id: 1, mine: true, text: "Сегодня делаем ноги или спину? 🤔"),
        .init(id: 2, mine: false, text: "", voice: true),
        .init(id: 3, mine: false, text: "Ноги. Приседания 4×8 и выпады.", reply: "Сегодня делаем ноги или спину?"),
        .init(id: 4, mine: true, text: "Принято! Отправлю видео техники после тренировки 💪"),
    ]

    var body: some View {
        VStack(spacing: 6) {
            Text("Сегодня")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.white.opacity(0.08), in: Capsule())
                .padding(.bottom, 4)
            ForEach(msgs) { m in
                HStack {
                    if m.mine { Spacer(minLength: 50) }
                    VStack(alignment: .leading, spacing: 5) {
                        if let r = m.reply {
                            HStack(spacing: 6) {
                                Capsule().fill(Color.lime).frame(width: 3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Вы").font(.system(size: fontSize * 0.8, weight: .bold)).foregroundStyle(Color.lime)
                                    Text(r).font(.system(size: fontSize * 0.8)).lineLimit(1)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.lime.opacity(0.1), in: RoundedRectangle(cornerRadius: min(radius, 10), style: .continuous))
                        }
                        if m.voice {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill").font(.headline).foregroundStyle(.black)
                                    .frame(width: 40, height: 40).background(Color.lime, in: Circle())
                                HStack(spacing: 2) {
                                    ForEach(0..<22, id: \.self) { i in Capsule().frame(width: 3, height: CGFloat(5 + (i * 7) % 17)) }
                                }
                                .opacity(0.5)
                                Text("0:23").font(.system(size: fontSize * 0.75)).opacity(0.6)
                            }
                        } else {
                            Text(m.text).font(.system(size: fontSize))
                        }
                        Text("23:20").font(.system(size: fontSize * 0.68)).opacity(0.55)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(m.mine ? Color.oxBg : Color.primary)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: m.mine ? radius : min(6, radius),
                                               bottomTrailingRadius: m.mine ? min(6, radius) : radius, topTrailingRadius: radius, style: .continuous)
                            .fill(m.mine ? Color.lime : Color.white.opacity(0.09))
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    if !m.mine { Spacer(minLength: 50) }
                }
            }
        }
        .padding(14)
        .animation(.spring(duration: 0.35), value: fontSize)
        .animation(.spring(duration: 0.35), value: radius)
    }
}

// MARK: размер текста

struct TextSizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("text_system") private var system = true
    @AppStorage("text_size") private var index = 3
    @AppStorage("bubble_radius") private var radius: Double = 20
    @State private var draftSystem = true
    @State private var draft = 3

    var body: some View {
        VStack(spacing: 0) {
            Text("Размер текста").font(.headline).padding(.top, 22)
            ScrollView {
                ChatPreview(fontSize: draftSystem ? 16 : Look.chatPoints[draft], radius: radius)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .defaultScrollAnchor(.bottom)
            .background(
                LinearGradient(colors: [Color.lime.opacity(0.08), Color.oxBg], startPoint: .top, endPoint: .bottom)
            )

            VStack(spacing: 0) {
                Toggle("Системный размер текста", isOn: $draftSystem.animation(.snappy))
                    .tint(Color.lime)
                    .padding(.vertical, 12)
                Divider()
                HStack(spacing: 12) {
                    Text("A").font(.system(size: 14))
                    StepSlider(value: $draft, count: Look.sizes.count)
                    Text("A").font(.system(size: 26))
                }
                .padding(.vertical, 14)
                .opacity(draftSystem ? 0.4 : 1)
                .disabled(draftSystem)
                Text(draftSystem ? "Как в настройках iPhone" : Look.names[draft])
                    .font(.footnote).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .padding(.bottom, 14)
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Text("Отмена").bold().frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.glass)
                    Button {
                        Haptic.success()
                        withAnimation(.snappy) { system = draftSystem; index = draft }
                        dismiss()
                    } label: { Text("Применить").bold().frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.glassProminent)
                        .tint(Color.lime).foregroundStyle(.black)
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .presentationDetents([.large])
        .presentationCornerRadius(34)
        .onAppear { draftSystem = system; draft = index }
    }
}

/// Ползунок с точками-шагами, как в Telegram
struct StepSlider: View {
    @Binding var value: Int
    let count: Int

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 30
            let step = w / CGFloat(max(1, count - 1))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(height: 4).padding(.horizontal, 15)
                Capsule().fill(Color.lime).frame(width: CGFloat(value) * step, height: 4).padding(.leading, 15)
                ForEach(0..<count, id: \.self) { i in
                    Circle().fill(i <= value ? Color.lime : .white.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .offset(x: 15 + CGFloat(i) * step - 3, y: 12)
                }
                Circle().fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .offset(x: 1 + CGFloat(value) * step)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let v = Int(((d.location.x - 15) / step).rounded())
                let c = min(max(v, 0), count - 1)
                if c != value {
                    Haptic.tap(.soft)
                    withAnimation(.spring(duration: 0.25, bounce: 0.3)) { value = c }
                }
            })
        }
        .frame(height: 30)
    }
}

// MARK: углы сообщений

struct BubbleCornersView: View {
    @AppStorage("bubble_radius") private var radius: Double = 20
    @AppStorage("text_system") private var system = true
    @AppStorage("text_size") private var index = 3

    var body: some View {
        List {
            Section {
                ChatPreview(fontSize: system ? 16 : Look.chatPoints[index], radius: radius)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(LinearGradient(colors: [Color.lime.opacity(0.08), Color.oxCard], startPoint: .top, endPoint: .bottom))
            }
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "square").font(.title3)
                    Slider(value: $radius, in: 0...24, step: 1) { _ in Haptic.tap(.soft) }
                        .tint(Color.lime)
                    Image(systemName: "capsule").font(.title3)
                }
            } header: {
                Text("Скругление · \(Int(radius))")
            } footer: {
                Text("Меняет форму пузырей во всех чатах.")
            }
        }
        .navigationTitle("Углы сообщений")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: анимации

struct AnimationSettingsView: View {
    @State private var p = PowerSaver.shared
    @AppStorage("anim_messages") private var messages = true
    @AppStorage("anim_send_haptic") private var sendHaptic = true

    var body: some View {
        List {
            Section {
                Toggle("Анимации интерфейса", isOn: Binding(get: { p.isOn(.interface) }, set: { p.set(.interface, $0) }))
                Toggle("Живые фоны", isOn: Binding(get: { p.isOn(.liveBackgrounds) }, set: { p.set(.liveBackgrounds, $0) }))
            } footer: {
                Text("Переходы, пружинки, жетоны с физикой, эмодзи на визитке. При низком заряде отключаются сами — см. «Энергосбережение».")
            }
            Section("Сообщения") {
                Toggle("Появление новых сообщений", isOn: $messages)
                Toggle("Вибрация при отправке", isOn: $sendHaptic)
            }
        }
        .tint(Color.lime)
        .navigationTitle("Анимации")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: иконка приложения

struct AppIconPicker: View {
    struct Icon: Identifiable { let id: String?; let title: String; let preview: String }
    static let all: [Icon] = [
        .init(id: nil, title: "Основная", preview: "icon-main"),
        .init(id: "AppIcon-Ocean", title: "Океан", preview: "icon-ocean"),
        .init(id: "AppIcon-Sunset", title: "Закат", preview: "icon-sunset"),
        .init(id: "AppIcon-Violet", title: "Фиолет", preview: "icon-violet"),
        .init(id: "AppIcon-Gold", title: "Золото", preview: "icon-gold"),
        .init(id: "AppIcon-Ruby", title: "Рубин", preview: "icon-ruby"),
        .init(id: "AppIcon-Ice", title: "Лёд", preview: "icon-ice"),
        .init(id: "AppIcon-Night", title: "Ночь", preview: "icon-night"),
        .init(id: "AppIcon-Forest", title: "Лес", preview: "icon-forest"),
        .init(id: "AppIcon-Light", title: "Светлая", preview: "icon-light"),
    ]

    @State private var current = UIApplication.shared.alternateIconName

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
            ForEach(Self.all, id: \.title) { icon in
                let on = current == icon.id
                Button { set(icon) } label: {
                    VStack(spacing: 7) {
                        Image(icon.preview)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .padding(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(on ? Color.lime : .white.opacity(0.1), lineWidth: on ? 2.5 : 1)
                            )
                            .scaleEffect(on ? 1.04 : 1)
                        Text(icon.title)
                            .font(.caption.weight(on ? .bold : .medium))
                            .foregroundStyle(on ? Color.lime : .primary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.4), value: current)
    }

    private func set(_ icon: Icon) {
        guard UIApplication.shared.supportsAlternateIcons, current != icon.id else { return }
        Haptic.tap()
        UIApplication.shared.setAlternateIconName(icon.id) { err in
            Task { @MainActor in
                if let err { OxAlert.error(err.localizedDescription) } else { current = icon.id }
            }
        }
    }
}
