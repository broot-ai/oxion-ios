import WidgetKit
import SwiftUI
import AppIntents

// Пункт управления iOS 18+: кнопки OXION. Каждая открывает нужный раздел приложения,
// даже если оно было закрыто (OpenOxionIntent выполняется при запуске OXION).

struct StartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ru.oxion.app.control.start") {
            ControlWidgetButton(action: OpenOxionIntent(route: "workout")) {
                Label("Тренировка", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .displayName("Начать тренировку")
        .description("Открыть текущую или сегодняшнюю тренировку")
    }
}

struct RestTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ru.oxion.app.control.rest") {
            ControlWidgetButton(action: OpenOxionIntent(route: "workout")) {
                Label("Отдых", systemImage: "timer")
            }
        }
        .displayName("Таймер отдыха")
        .description("Перейти к активной тренировке и таймеру отдыха")
    }
}

struct FavoritesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ru.oxion.app.control.favorites") {
            ControlWidgetButton(action: OpenOxionIntent(route: "favorites")) {
                Label("Избранные", systemImage: "heart.fill")
            }
        }
        .displayName("Избранные тренеры")
        .description("Открыть избранных тренеров OXION")
    }
}

struct ActivityControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ru.oxion.app.control.activity") {
            ControlWidgetButton(action: OpenOxionIntent(route: "diary")) {
                Label("Активность", systemImage: "chart.bar.fill")
            }
        }
        .displayName("Моя активность")
        .description("Дневник и статистика недели")
    }
}
