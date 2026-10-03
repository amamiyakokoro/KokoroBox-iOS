import AppIntents
import Foundation

// Compile the same intent in both targets so WidgetKit can dispatch it to the
// app process, where the existing subscription and authentication APIs live.
@available(iOS 16.0, *)
struct RefreshDashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Update subscription"

    func perform() async throws -> some IntentResult {
        #if KOKORO_WIDGET_EXTENSION
            // The app's ForegroundContinuableIntent conformance routes execution
            // to its process without bringing its interface to the foreground.
            throw NSError(domain: "WidgetSubscriptionUpdate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Open KokoroBox to update the subscription.",
            ])
        #else
            try await WidgetSubscriptionUpdater.update()
        #endif
        return .result()
    }
}

#if !KOKORO_WIDGET_EXTENSION
    @available(iOS 16.0, *)
    extension RefreshDashboardIntent: ForegroundContinuableIntent {}
#endif
