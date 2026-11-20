import Foundation
import AVFoundation
import Speech
import Observation
import SwiftUI

// MARK: - OXION Audio Coach: голосовое сопровождение тренировки

/// Говорит по событиям движка тренировки (WorkoutEngine.onEvent) и по реальным повторам из камеры (PoseCounter).
/// Аудиосессия включается только на время фразы: музыка приглушается и потом возвращается.
@MainActor
@Observable
final class AudioCoach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioCoach()

    enum Detail: String, CaseIterable, Identifiable {
        case minimal, normal, detailed
        var id: String { rawValue }
        var title: String { self == .minimal ? "Минимум" : self == .normal ? "Обычно" : "Подробно" }
        var hint: String {
            switch self {
            case .minimal: return "Только старт, конец отдыха и итог"
            case .normal: return "Подходы, отдых за 15 секунд, «осталось 2 повторения»"
            case .detailed: return "Плюс счёт каждого повтора и отсчёт 3-2-1"
            }
        }
    }

    private let d = UserDefaults.standard
    var enabled: Bool { didSet { d.set(enabled, forKey: "coach_on"); if !enabled { synth.stopSpeaking(at: .immediate) } } }
    var voiceId: String { didSet { d.set(voiceId, forKey: "coach_voice") } }
    var volume: Float { didSet { d.set(volume, forKey: "coach_volume") } }
    var rate: Float { didSet { d.set(rate, forKey: "coach_rate") } }
    var detail: Detail { didSet { d.set(detail.rawValue, forKey: "coach_detail") } }
    var countReps: Bool { didSet { d.set(countReps, forKey: "coach_reps") } }
    /// Камера достигла цели подхода → записать подход автоматически
    var autoRecord: Bool { didSet { d.set(autoRecord, forKey: "coach_autorec") } }

    private(set) var speaking = false
    private(set) var lastPhrase = ""
    private let synth = AVSpeechSynthesizer()
    private var restTask: Task<Void, Never>?
    private var spokenMarks: Set<Int> = []

    override private init() {
        enabled = d.object(forKey: "coach_on") as? Bool ?? true
        voiceId = d.string(forKey: "coach_voice") ?? ""
        volume = d.object(forKey: "coach_volume") as? Float ?? 1
        rate = d.object(forKey: "coach_rate") as? Float ?? 1
        detail = Detail(rawValue: d.string(forKey: "coach_detail") ?? "") ?? .normal
        countReps = d.object(forKey: "coach_reps") as? Bool ?? true
        autoRecord = d.object(forKey: "coach_autorec") as? Bool ?? false
        super.init()
        synth.delegate = self
    }

    /// Подключить к движку тренировки (вызывается при запуске приложения)
    func attach() {
        WorkoutEngine.onEvent = { e, s in AudioCoach.shared.handle(e, s) }
        if let s = WorkoutEngine.shared.state, s.phase == .resting { watchRest(s) }
    }

    // MARK: Голоса

    static var russianVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ru") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    var voice: AVSpeechSynthesisVoice? {
        if !voiceId.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voiceId) { return v }
        return Self.russianVoices.first ?? AVSpeechSynthesisVoice(language: "ru-RU")
    }

    /// Куда идёт звук: динамик, AirPods, наушники
    var outputName: String {
        let o = AVAudioSession.sharedInstance().currentRoute.outputs.first
        guard let o else { return "Динамик iPhone" }
        switch o.portType {
        case .builtInSpeaker, .builtInReceiver: return "Динамик iPhone"
        default: return o.portName
        }
    }

    var isHeadphones: Bool {
        guard let t = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType else { return false }
        let ports: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .usbAudio]
        return ports.contains(t)
    }

    // MARK: Речь

    func say(_ text: String, interrupt: Bool = false, force: Bool = false) {
        guard enabled || force else { return }
        activateSession()
        if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.volume = volume
        u.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        u.postUtteranceDelay = 0.05
        lastPhrase = text
        speaking = true
        synth.speak(u)
    }

    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        if !VoiceCommands.shared.listening {
            try? s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        }
        try? s.setActive(true)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedSpeaking() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedSpeaking() }
    }

    private func finishedSpeaking() {
        guard !synth.isSpeaking else { return }
        speaking = false
        VoiceCommands.shared.speechEnded = Date()
        // вернуть громкость музыке
        if !VoiceCommands.shared.listening {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: События тренировки

    func handle(_ e: WorkoutEngine.Event, _ s: WorkoutState) {
        switch e {
        case .started:
            guard let it = s.currentItem else { return }
            if detail == .minimal {
                say("Начинаем. \(it.name).")
            } else {
                say("Начинаем тренировку. Первое упражнение — \(it.name). \(setsText(it)).")
            }
        case .setDone:
            restTask?.cancel()
            guard s.phase != .finished else { return }
            if s.phase == .resting {
                let left = Int((s.restEndsAt ?? Date()).timeIntervalSinceNow.rounded())
                var t = detail == .minimal ? "" : "Подход завершён. Начинается отдых — \(secText(left))."
                if detail != .minimal, let it = s.currentItem, it.doneSets == 0 {
                    t += " Следующее упражнение — \(it.name)."
                }
                if !t.isEmpty { say(t, interrupt: true) }
                watchRest(s)
            } else if let it = s.currentItem {
                say("Подход завершён. \(nextSetText(it))", interrupt: true)
            }
        case .restSkipped:
            restTask?.cancel()
            if let it = s.currentItem, detail != .minimal { say(nextSetText(it), interrupt: true) }
        case .paused:
            restTask?.cancel()
            if detail != .minimal { say("Тренировка на паузе.") }
        case .resumed:
            if detail != .minimal { say("Продолжаем.") }
            if s.phase == .resting { watchRest(s) }
        case .finished:
            restTask?.cancel()
            let min = Int(s.elapsed(s.finishedAt ?? Date()) / 60)
            let sets = s.setsDoneAll
            say("Тренировка завершена. Время — \(min) \(RU.plural(min, "минута", "минуты", "минут")), \(sets) \(RU.plural(sets, "подход", "подхода", "подходов")). Отличная работа!", interrupt: true)
        }
    }

    /// Следим за отдыхом: «15 секунд», «3-2-1», «отдых окончен»
    private func watchRest(_ s: WorkoutState) {
        restTask?.cancel()
        spokenMarks = []
        guard let end = s.restEndsAt else { return }
        restTask = Task { [weak self] in
            while !Task.isCancelled {
                let left = Int(end.timeIntervalSinceNow.rounded(.up))
                guard let self else { return }
                guard WorkoutEngine.shared.state?.phase == .resting, WorkoutEngine.shared.state?.restEndsAt == end else { return }
                if left <= 0 {
                    if let it = WorkoutEngine.shared.state?.currentItem {
                        self.say("Отдых окончен. \(self.nextSetText(it))", interrupt: true)
                    }
                    return
                }
                if self.detail != .minimal, left == 15, !self.spokenMarks.contains(15) {
                    self.spokenMarks.insert(15)
                    let nextName = WorkoutEngine.shared.state?.currentItem
                    let isNewEx = (nextName?.doneSets ?? 1) == 0
                    self.say(isNewEx ? "До следующего упражнения 15 секунд." : "До следующего подхода 15 секунд.")
                }
                if self.detail == .detailed, left == 30, !self.spokenMarks.contains(30) {
                    self.spokenMarks.insert(30)
                    self.say("Ещё 30 секунд отдыха.")
                }
                if self.detail == .detailed, (1...3).contains(left), !self.spokenMarks.contains(left) {
                    self.spokenMarks.insert(left)
                    self.say(["", "один", "два", "три"][left], interrupt: true)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // MARK: Повторы из камеры (реальные данные Vision)

    /// Вызывается PoseCounter при каждом засчитанном повторе
    func repCounted(_ n: Int, target: Int?) {
        guard enabled, countReps else { return }
        if let target, target > 0 {
            let left = target - n
            if left == 0 {
                say("Подход выполнен!", interrupt: true)
            } else if left > 0 && left <= 3 && detail != .minimal {
                let w = left == 1 ? "Осталось одно повторение" : left == 2 ? "Осталось два повторения" : "Осталось три повторения"
                say(detail == .detailed ? "\(n). \(w)." : "\(w).", interrupt: true)
            } else if detail == .detailed || (left < 0 && detail == .normal) {
                say("\(n)", interrupt: true)
            }
        } else {
            if detail == .detailed || (detail == .normal && n % 5 == 0) { say("\(n)", interrupt: true) }
        }
    }

    func sayRestLeft() {
        guard let s = WorkoutEngine.shared.state else { say("Тренировка не начата.", force: true); return }
        if s.phase == .resting {
            say("Отдыха осталось \(secText(Int(s.restLeft().rounded())))", interrupt: true, force: true)
        } else if let it = s.currentItem {
            say("Сейчас: \(it.name). \(nextSetText(it))", interrupt: true, force: true)
        }
    }

    // MARK: Тексты

    private func setsText(_ it: PlanItem) -> String {
        var t = "\(it.sets) \(RU.plural(it.sets, "подход", "подхода", "подходов"))"
        if it.type == "t" { t += " по \(secText(it.reps))" }
        else if it.type != "dt" { t += " по \(it.reps) \(RU.plural(it.reps, "повторению", "повторения", "повторений"))" }
        if it.type == "wr", let w = it.weight, w > 0 { t += ", вес \(num(w)) \(it.unit)" }
        return t
    }

    private func nextSetText(_ it: PlanItem) -> String {
        let k = min(it.doneSets + 1, it.sets)
        var t = "Подход \(k) из \(it.sets). \(it.name)"
        if it.type == "wr", let w = it.weight, w > 0 { t += ", \(num(w)) \(it.unit)" }
        if it.type == "r" || it.type == "wr" { t += ", \(it.reps) \(RU.plural(it.reps, "повторение", "повторения", "повторений"))" }
        return t + "."
    }

    private func secText(_ s: Int) -> String {
        if s >= 60 {
            let m = s / 60, r = s % 60
            return "\(m) \(RU.plural(m, "минута", "минуты", "минут"))" + (r > 0 ? " \(r) \(RU.plural(r, "секунда", "секунды", "секунд"))" : "")
        }
        return "\(s) \(RU.plural(s, "секунда", "секунды", "секунд"))"
    }

    private func num(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Голосовые команды без Siri (распознавание речи на устройстве)

/// Слушает микрофон только пока открыт экран тренировки и включён переключатель.
/// Команды: «готово», «дальше», «пауза», «продолжить», «сколько».
@MainActor
@Observable
final class VoiceCommands {
    static let shared = VoiceCommands()

    private(set) var listening = false
    private(set) var lastHeard = ""
    private(set) var lastCommand = ""
    var speechEnded = Date.distantPast

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var handledWords = 0
    private var lastCommandAt = Date.distantPast

    static let commands: [(words: [String], title: String)] = [
        (["готово", "сделал", "сделала", "сделано"], "«Готово» — записать подход"),
        (["дальше", "пропусти", "пропустить", "следующий"], "«Дальше» — пропустить отдых"),
        (["пауза", "стоп"], "«Пауза» — поставить на паузу"),
        (["продолжить", "продолжаем", "поехали"], "«Продолжить» — снять с паузы"),
        (["сколько"], "«Сколько?» — сколько осталось отдыха")
    ]

    func toggle() async {
        if listening { stop() } else { await start() }
    }

    func start() async {
        guard !listening else { return }
        let auth: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard auth == .authorized else {
            OxAlert.show(icon: "mic.slash.fill", tint: Color(hex: 0xF0A030), title: "Нет доступа к распознаванию речи",
                         message: "Разрешите: Настройки → Oxion → Распознавание речи.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            OxAlert.show(icon: "mic.slash.fill", tint: Color(hex: 0xF0A030), title: "Нет доступа к микрофону",
                         message: "Разрешите: Настройки → Oxion → Микрофон.")
            return
        }
        guard let r = recognizer, r.isAvailable else {
            OxAlert.error("Распознавание русской речи сейчас недоступно на этом iPhone.")
            return
        }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
            try s.setActive(true)
            listening = true
            try begin(r)
        } catch {
            listening = false
            OxAlert.error("Не удалось включить микрофон: \(error.localizedDescription)")
        }
    }

    private func begin(_ r: SFSpeechRecognizer) throws {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.contextualStrings = Self.commands.flatMap { $0.words }
        request = req
        handledWords = 0
        let input = audio.inputNode
        Self.tap(input, req)
        audio.prepare()
        try audio.start()
        task = Self.recognize(r, req) { text, final, failed in
            Task { @MainActor in VoiceCommands.shared.onResult(text, final: final, failed: failed) }
        }
    }

    nonisolated private static func tap(_ input: AVAudioInputNode, _ req: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        let fmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
    }

    nonisolated private static func recognize(_ r: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest,
                                              _ cb: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        r.recognitionTask(with: req) { result, error in
            cb(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private func onResult(_ text: String?, final: Bool, failed: Bool) {
        guard listening else { return }
        if let text {
            let words = text.lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
            if words.count > handledWords {
                let fresh = Array(words[handledWords...])
                handledWords = words.count
                lastHeard = fresh.joined(separator: " ")
                // не реагируем на собственный голос тренера
                let coachBusy = AudioCoach.shared.speaking || Date().timeIntervalSince(speechEnded) < 0.8
                if !coachBusy, let cmd = fresh.lazy.compactMap({ self.match($0) }).first {
                    run(cmd)
                }
            }
        }
        if final || failed {
            // перезапуск распознавания (у Apple ограничение на длину сессии)
            restart()
        }
    }

    private func match(_ w: String) -> Int? {
        Self.commands.firstIndex { $0.words.contains(w) }
    }

    private func run(_ i: Int) {
        guard Date().timeIntervalSince(lastCommandAt) > 1.5 else { return }
        lastCommandAt = Date()
        let e = WorkoutEngine.shared
        let phase = e.state?.phase
        OxHaptics.play(.select)
        switch i {
        case 0:
            if phase == .exercising || phase == .resting { e.completeSet(); lastCommand = "Подход записан" }
        case 1:
            if phase == .resting { e.nextSet(); lastCommand = "Отдых пропущен" }
        case 2:
            if phase == .exercising || phase == .resting { e.pause(); lastCommand = "Пауза" }
        case 3:
            if phase == .paused { e.resume(); lastCommand = "Продолжаем" }
        default:
            AudioCoach.shared.sayRestLeft(); lastCommand = "Сколько осталось"
        }
    }

    private func restart() {
        teardown()
        guard listening, let r = recognizer else { return }
        try? begin(r)
    }

    private func teardown() {
        audio.stop()
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    func stop() {
        guard listening else { return }
        listening = false
        teardown()
        lastHeard = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
