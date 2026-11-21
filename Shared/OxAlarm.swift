import Foundation
import AlarmKit

/// Данные будильника OXION (общие для приложения и виджета, который рисует отсчёт)
struct OxAlarmMeta: AlarmMetadata {
    var kind: String = "rest"      // rest — конец отдыха, remind — напоминание о тренировке
    var next: String = ""          // следующее упражнение
}
