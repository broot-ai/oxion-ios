import Foundation
import ActivityKit

/// Настоящая Live Activity «OXION — Синхронизация» для Dynamic Island и экрана блокировки.
/// Пока OXION открыт, iOS её не показывает; видна, если свернуть приложение во время синхронизации или отправки.
struct OxionSyncAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var done: Bool
        var title: String      // «Синхронизация», «Отправка публикации»…
        var doneText: String   // «Всё актуально», «Опубликовано»
        var started: Date
    }
    var kind: String
}

#if !WIDGET_EXT
@MainActor
enum SyncIsland {
    private static var current: Activity<OxionSyncAttributes>?

    static func start(title: String, doneText: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await finish(nil, success: true, immediate: true)
        let st = OxionSyncAttributes.ContentState(done: false, title: title, doneText: doneText, started: Date())
        current = try? Activity.request(attributes: OxionSyncAttributes(kind: "sync"),
                                        content: ActivityContent(state: st, staleDate: Date().addingTimeInterval(120)),
                                        pushType: nil)
    }

    /// Кольцо замыкается, галочка — и через пару секунд остров сжимается
    static func finish(_ text: String?, success: Bool, immediate: Bool = false) async {
        guard let a = current else { return }
        current = nil
        var st = a.content.state
        st.done = true
        if let text { st.doneText = text }
        if !success { st.doneText = "Не получилось — откройте OXION" }
        let content = ActivityContent(state: st, staleDate: nil)
        await a.update(content)
        await a.end(content, dismissalPolicy: immediate ? .immediate : .after(Date().addingTimeInterval(2.5)))
    }
}
#endif
