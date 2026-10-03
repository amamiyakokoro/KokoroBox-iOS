#if os(iOS)
import Foundation
import Libbox
import Library
import WidgetKit

/// A local dashboard snapshot; WidgetKit does not provide continuous traffic updates.
@MainActor
enum DashboardWidgetSnapshot {
    private static var lastReload = Date.distantPast

    static func save(profileName: String?, client: CommandClient, forceReload: Bool = false) {
        guard !Variant.screenshotMode,
              let defaults = UserDefaults(suiteName: AppConfiguration.appGroupID)
        else { return }

        var snapshot = defaults.dictionary(forKey: "dashboard_widget_snapshot") ?? [:]
        snapshot["profileName"] = profileName ?? String(localized: "No profile")
        snapshot["mode"] = client.clashMode
        if let groups = client.groups {
            // Prefer an interactive selector; URL-test groups are a fallback.
            let group = groups.first { $0.selectable && !$0.selected.isEmpty }
                ?? groups.first { !$0.selected.isEmpty }
            snapshot["groupName"] = group?.tag ?? ""
            snapshot["selectedOutbound"] = group?.selected ?? ""
        }
        if let status = client.status {
            snapshot["download"] = LibboxFormatBytes(status.downlinkTotal)
            snapshot["upload"] = LibboxFormatBytes(status.uplinkTotal)
            snapshot["downloadSpeed"] = "\(LibboxFormatBytes(status.downlink))/s"
            snapshot["uploadSpeed"] = "\(LibboxFormatBytes(status.uplink))/s"
            snapshot["connections"] = "\(status.connectionsOut)"
            snapshot["memory"] = LibboxFormatMemoryBytes(status.memory)
            snapshot["updatedAt"] = Date()
        }
        defaults.set(snapshot, forKey: "dashboard_widget_snapshot")
        // Status messages arrive every second; avoid spending WidgetKit's reload budget per tick.
        if forceReload || Date().timeIntervalSince(lastReload) >= 900 {
            lastReload = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: "\(AppConfiguration.packageName).widget.Dashboard")
        }
    }
}
#endif
