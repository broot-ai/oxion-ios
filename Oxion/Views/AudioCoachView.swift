import SwiftUI
import AVFoundation

// MARK: - Настройки голосового тренера

struct AudioCoachSettingsView: View {
    @State private var coach = AudioCoach.shared
    @State private var route = AudioCoach.shared.outputName
    @State private var headphones = AudioCoach.shared.isHeadphones
    private let voices = AudioCoach.russianVoices

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.lime.opacity(0.18)).frame(width: 56, height: 56)
                        Image(systemName: coach.speaking ? "waveform" : "person.wave.2.fill")
                            .font(.title2).foregroundStyle(Color.lime)
                            .symbolEffect(.variableColor.iterative, isActive: coach.speaking)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Голосовой тренер").font(.title3.bold())
                        Text("Объявляет упражнения, отдых, считает повторы с камеры и подводит итог.")
                            .font(.caption).foregroundStyle(Color.oxHint)
                    }
                }
                .listRowBackground(Color.clear)
                Toggle("Голосовые подсказки", isOn: $coach.enabled).tint(Color.lime)
            }

            Section {
                HStack {
                    Label(route, systemImage: headphones ? "airpods" : "speaker.wave.2.fill")
                    Spacer()
                    Text(headphones ? "Наушники" : "Динамик").font(.caption).foregroundStyle(Color.oxHint)
                }
                Button {
                    coach.say("Привет! Я твой тренер OXION. Подход завершён. Начинается отдых — 60 секунд.", interrupt: true, force: true)
                } label: { Label("Проверить голос", systemImage: "play.circle.fill") }
            } header: { Text("Звук") } footer: {
                Text("С AirPods подсказки звучат только в ушах. Музыка на время фразы приглушается и потом возвращается.")
            }

            Section("Сколько говорить") {
                Picker("", selection: $coach.detail) {
                    ForEach(AudioCoach.Detail.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(coach.detail.hint).font(.caption).foregroundStyle(Color.oxHint)
            }

            Section("Голос") {
                if voices.isEmpty {
                    Text("Русские голоса не найдены. Добавьте: Настройки → Универсальный доступ → Устное содержимое → Голоса → Русский.")
                        .font(.caption)
                }
                ForEach(voices, id: \.identifier) { v in
                    Button {
                        coach.voiceId = v.identifier
                        coach.say("Так звучит голос \(v.name).", interrupt: true, force: true)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(v.name).foregroundStyle(.white)
                                Text(quality(v)).font(.caption).foregroundStyle(Color.oxHint)
                            }
                            Spacer()
                            if coach.voice?.identifier == v.identifier {
                                Image(systemName: "checkmark").foregroundStyle(Color.lime)
                            }
                        }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Громкость").font(.subheadline)
                    Slider(value: $coach.volume, in: 0.2...1).tint(Color.lime)
                }
                VStack(alignment: .leading) {
                    Text("Скорость речи").font(.subheadline)
                    Slider(value: $coach.rate, in: 0.8...1.25).tint(Color.lime)
                }
            }

            Section {
                Toggle("Считать повторы вслух (камера)", isOn: $coach.countReps).tint(Color.lime)
                Toggle("Записывать подход, когда камера досчитала до цели", isOn: $coach.autoRecord).tint(Color.lime)
            } header: { Text("OXION Vision") } footer: {
                Text("Счёт берётся из распознавания движения камерой, а не из заранее заданных чисел.")
            }

            Section {
                ForEach(VoiceCommands.commands, id: \.title) { c in
                    Label(c.title, systemImage: "mic.fill")
                }
            } header: { Text("Голосовые команды") } footer: {
                Text("Включаются кнопкой с микрофоном на экране тренировки. Речь распознаётся на iPhone, микрофон работает только пока открыт экран тренировки. Ещё можно говорить «Привет, Siri» — команды есть в разделе Siri.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.oxBg)
        .navigationTitle("Голосовой тренер")
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            route = coach.outputName
            headphones = coach.isHeadphones
        }
    }

    private func quality(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "Премиум-качество"
        case .enhanced: return "Улучшенное качество"
        default: return "Обычное качество"
        }
    }
}
