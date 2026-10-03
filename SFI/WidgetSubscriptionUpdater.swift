import Foundation
import Library

@MainActor
enum WidgetSubscriptionUpdater {
    static let didFinish = Notification.Name("WidgetSubscriptionUpdateFinished")

    static func update() async throws {
        let profileID = await SharedPreferences.selectedProfileID.get()
        guard let profile = try await ProfileManager.get(profileID) else {
            throw updateError(String(localized: "No profile"))
        }
        guard profile.type == .remote else {
            throw updateError(String(localized: "The selected profile has no subscription to update."))
        }
        // Await the real update in perform(), so the system keeps the intent
        // running until completion and can report any error to the caller.
        try await profile.updateRemoteProfile()
        NotificationCenter.default.post(name: didFinish, object: nil)
    }

    private static func updateError(_ message: String) -> NSError {
        NSError(domain: "WidgetSubscriptionUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
