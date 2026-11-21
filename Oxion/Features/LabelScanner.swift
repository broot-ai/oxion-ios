import SwiftUI
import VisionKit

// MARK: - Сканер этикеток: камера читает «Пищевая ценность на 100 г» и считает порцию

struct Nutrition: Equatable {
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?
    var isEmpty: Bool { kcal == nil && protein == nil && fat == nil && carbs == nil }

    /// Ищет числа рядом со словами «ккал», «белки», «жиры», «углеводы»
    static func parse(_ text: String) -> Nutrition {
        let t = text.lowercased().replacingOccurrences(of: ",", with: ".")
        func num(after words: [String]) -> Double? {
            for w in words {
                guard let r = t.range(of: w) else { continue }
                let tail = t[r.upperBound...].prefix(40)
                if let m = tail.range(of: #"\d+(\.\d+)?"#, options: .regularExpression), let v = Double(tail[m]) { return v }
            }
            return nil
        }
        var n = Nutrition()
        // «энергетическая ценность 250 ккал» или «250 ккал»
        if let m = t.range(of: #"(\d+(\.\d+)?)\s*ккал"#, options: .regularExpression) {
            n.kcal = Double(t[m].replacingOccurrences(of: "ккал", with: "").trimmingCharacters(in: .whitespaces))
        } else {
            n.kcal = num(after: ["энергетическая ценность", "калорийность", "kcal"])
        }
        n.protein = num(after: ["белки", "белок", "белка", "protein"])
        n.fat = num(after: ["жиры", "жир", "fat"])
        n.carbs = num(after: ["углеводы", "углевод", "carbohydrate"])
        return n
    }
}

struct LabelScannerView: View {
    @State private var text = ""
    @State private var n = Nutrition()
    @State private var grams: Double = 100
    @State private var frozen = false

    private var supported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        VStack(spacing: 0) {
            if supported {
                ScannerRepresentable(frozen: frozen) { t in
                    text = t
                    let p = Nutrition.parse(t)
                    if !p.isEmpty && p != n {
                        n = p
                        OxHaptics.play(.select)
                    }
                }
                .frame(height: 320)
                .overlay(alignment: .bottom) {
                    Text(n.isEmpty ? "Наведите камеру на «Пищевая ценность на 100 г»" : "Нашли состав — можно заморозить кадр")
                        .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule).padding(10)
                }
            } else {
                ContentUnavailableView("Сканер недоступен", systemImage: "text.viewfinder",
                                       description: Text("Нужен доступ к камере: Настройки → Oxion → Камера."))
                    .frame(height: 320)
            }

            List {
                Section("На 100 г") {
                    row("Калории", n.kcal, "ккал")
                    row("Белки", n.protein, "г")
                    row("Жиры", n.fat, "г")
                    row("Углеводы", n.carbs, "г")
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("Порция: \(Int(grams)) г").font(.subheadline.bold())
                        Slider(value: $grams, in: 10...600, step: 10).tint(Color.lime)
                    }
                    let k = grams / 100
                    HStack {
                        total("\(Int((n.kcal ?? 0) * k))", "ккал")
                        total(String(format: "%.0f", (n.protein ?? 0) * k), "белки")
                        total(String(format: "%.0f", (n.fat ?? 0) * k), "жиры")
                        total(String(format: "%.0f", (n.carbs ?? 0) * k), "углев.")
                    }
                } header: { Text("В порции") }
                Section {
                    Toggle("Заморозить кадр", isOn: $frozen).tint(Color.lime)
                } footer: {
                    Text("Текст читается прямо на iPhone. Значения приблизительные — проверьте по упаковке.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color.oxBg)
        .navigationTitle("Сканер этикеток")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ t: String, _ v: Double?, _ u: String) -> some View {
        HStack {
            Text(t)
            Spacer()
            Text(v.map { String(format: $0.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", $0) + " " + u } ?? "—")
                .bold().foregroundStyle(v == nil ? Color.oxHint : Color.lime)
        }
    }

    private func total(_ v: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold().monospacedDigit())
            Text(t).font(.caption2).foregroundStyle(Color.oxHint)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    var frozen: Bool
    var onText: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["ru-RU", "en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onText = onText
        if frozen, vc.isScanning { vc.stopScanning() }
        if !frozen, !vc.isScanning { try? vc.startScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            let text = items.compactMap { item -> String? in
                if case .text(let t) = item { return t.transcript }
                return nil
            }.joined(separator: "\n")
            onText(text)
        }
    }
}
