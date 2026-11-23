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

/// Ссылка на камеру сканера — чтобы сделать снимок кадра
@MainActor final class ScannerHandle {
    weak var vc: DataScannerViewController?
    func photo() async -> UIImage? { try? await vc?.capturePhoto() }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    var frozen: Bool
    var handle: ScannerHandle? = nil
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
        handle?.vc = vc
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
