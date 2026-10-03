import AppIntents
import SwiftUI
import WidgetKit

struct DashboardEntry: TimelineEntry {
    var date: Date
    var isStarted = false
    var subscriptionUpdateStartedAt: Date?
    // Recover if the app exits before it can publish completion.
    static let subscriptionUpdateTimeout: TimeInterval = 300

    var isUpdatingSubscription: Bool {
        guard let subscriptionUpdateStartedAt else { return false }
        let age = date.timeIntervalSince(subscriptionUpdateStartedAt)
        return age >= 0 && age < Self.subscriptionUpdateTimeout
    }

    var serviceStatus: String {
        isUpdatingSubscription ? "UPDATING" : (isStarted ? "RUNNING" : "STOPPED")
    }
    var profileName = String(localized: "Open app to select a profile")
    var mode = ""
    var groupName = ""
    var selectedOutbound = ""
    var download = "—"
    var upload = "—"
    var downloadSpeed = "—"
    var uploadSpeed = "—"
    var connections = "—"
    var memory = "—"
    var updatedAt: Date?

    static let preview = DashboardEntry(
        date: .now, isStarted: true, profileName: "Kokoro Hong Kong ANYTLS", mode: "rule",
        groupName: "Kokoro", selectedOutbound: "Hong Kong ANYTLS",
        download: "399 KB", upload: "277 KB", downloadSpeed: "1.5 KB/s",
        uploadSpeed: "0 KB/s", connections: "19", memory: "19 MB", updatedAt: .now
    )

    static var stoppedPreview: DashboardEntry {
        var entry = preview
        entry.isStarted = false
        return entry
    }

    static var updatingPreview: DashboardEntry {
        var entry = preview
        entry.subscriptionUpdateStartedAt = entry.date
        return entry
    }
}

struct DashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
        } else {
            Task { completion(await entry()) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        Task {
            let value = await entry()
            if value.isUpdatingSubscription, let startedAt = value.subscriptionUpdateStartedAt {
                var expired = value
                expired.date = startedAt.addingTimeInterval(DashboardEntry.subscriptionUpdateTimeout)
                expired.subscriptionUpdateStartedAt = nil
                completion(Timeline(entries: [value, expired], policy: .after(expired.date)))
            } else {
                completion(Timeline(entries: [value], policy: .after(Date().addingTimeInterval(900))))
            }
        }
    }

    private func entry() async -> DashboardEntry {
        var value = DashboardEntry(date: .now)
        value.isStarted = (try? await WidgetTunnelControl.currentIsStarted()) ?? false
        let defaults = UserDefaults(suiteName: WidgetAppConfiguration.appGroupID)
        value.subscriptionUpdateStartedAt = defaults?.object(forKey: "dashboard_widget_subscription_update_started_at") as? Date
        let snapshot = defaults?.dictionary(forKey: "dashboard_widget_snapshot") ?? [:]
        value.profileName = snapshot["profileName"] as? String ?? value.profileName
        value.mode = snapshot["mode"] as? String ?? ""
        value.groupName = snapshot["groupName"] as? String ?? ""
        value.selectedOutbound = snapshot["selectedOutbound"] as? String ?? ""
        value.download = snapshot["download"] as? String ?? "—"
        value.upload = snapshot["upload"] as? String ?? "—"
        value.downloadSpeed = snapshot["downloadSpeed"] as? String ?? "—"
        value.uploadSpeed = snapshot["uploadSpeed"] as? String ?? "—"
        value.connections = snapshot["connections"] as? String ?? "—"
        value.memory = snapshot["memory"] as? String ?? "—"
        value.updatedAt = snapshot["updatedAt"] as? Date
        return value
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "\(WidgetAppConfiguration.packageName).widget.Dashboard",
            provider: DashboardProvider()
        ) { entry in
            DashboardWidgetContent(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(white: 0.20), Color(white: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Connection dashboard")
        .description("Profile, traffic and VPN controls.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DashboardWidgetContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: DashboardEntry

    var body: some View {
        if family == .systemSmall {
            SmallProxyWidgetView(entry: entry)
        } else {
            DashboardWidgetView(entry: entry)
        }
    }
}

struct SmallProxyWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text("KokoroBox")
                    .font(.system(size: 19, weight: .semibold))
                Text(entry.serviceStatus)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 0)

            Grid(horizontalSpacing: 6, verticalSpacing: 7) {
                GridRow {
                    WidgetMetric(symbol: "arrow.down", value: entry.download, label: "Downloaded")
                    WidgetMetric(symbol: "arrow.up", value: entry.upload, label: "Uploaded")
                }
                GridRow {
                    WidgetMetric(symbol: "arrow.down.circle", value: entry.downloadSpeed, label: "Download speed")
                    WidgetMetric(symbol: "arrow.up.circle", value: entry.uploadSpeed, label: "Upload speed")
                }
            }
            .foregroundStyle(.white.opacity(0.65))

            Spacer(minLength: 0)

            HStack {
                WidgetServiceButton(isStarted: entry.isStarted)

                Spacer(minLength: 0)

                WidgetSubscriptionRefreshButton(isUpdating: entry.isUpdatingSubscription, size: 32)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .widgetURL(URL(string: "sing-box://widget?page=dashboard"))
    }

}

struct DashboardWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("KokoroBox")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(entry.serviceStatus)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                WidgetSubscriptionRefreshButton(isUpdating: entry.isUpdatingSubscription, size: 28)
                    .font(.system(size: 14))
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    metric("arrow.down", entry.download, label: "Downloaded")
                    metric("arrow.up", entry.upload, label: "Uploaded")
                    metric("link", entry.connections, label: "Outbound connections")
                }
                GridRow {
                    metric("arrow.down.circle", entry.downloadSpeed, label: "Download speed")
                    metric("arrow.up.circle", entry.uploadSpeed, label: "Upload speed")
                    metric("memorychip", entry.memory, label: "Memory")
                }
            }
            .foregroundStyle(.white.opacity(0.65))

            HStack(spacing: 12) {
                Text(entry.profileName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .foregroundStyle(.white.opacity(0.7))
                WidgetServiceButton(isStarted: entry.isStarted)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .widgetURL(URL(string: "sing-box://widget?page=dashboard"))
    }

    private func metric(_ symbol: String, _ value: String, label: LocalizedStringKey) -> some View {
        WidgetMetric(symbol: symbol, value: value, label: label)
    }
}

struct WidgetMetric: View {
    let symbol: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .frame(width: 13)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(value)
    }
}

struct WidgetServiceButton: View {
    let isStarted: Bool

    var body: some View {
        Button(intent: ToggleServiceControlIntent(value: !isStarted)) {
            Image(systemName: "power")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(isStarted ? Color.green : Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStarted ? Text("Stop VPN") : Text("Start VPN"))
        .accessibilityValue(isStarted ? Text("Running") : Text("Stopped"))
    }
}

struct RefreshDashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Update subscription"

    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(URL(string: "sing-box://widget?page=update-profile")!))
    }
}

struct WidgetSubscriptionRefreshButton: View {
    let isUpdating: Bool
    let size: CGFloat
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Button(intent: RefreshDashboardIntent()) {
            Image(systemName: "arrow.clockwise")
                .frame(width: size, height: size)
                .rotationEffect(.degrees(isUpdating ? 360 : 0))
                .animation(isLuminanceReduced ? nil : .linear(duration: 1), value: isUpdating)
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .accessibilityLabel(isUpdating ? Text("Updating subscription") : Text("Update subscription"))
    }
}

#Preview(as: .systemMedium) {
    DashboardWidget()
} timeline: {
    DashboardEntry.preview
    DashboardEntry.updatingPreview
    DashboardEntry.preview
    DashboardEntry.stoppedPreview
}

#Preview(as: .systemSmall) {
    DashboardWidget()
} timeline: {
    DashboardEntry.preview
    DashboardEntry.updatingPreview
    DashboardEntry.preview
    DashboardEntry.stoppedPreview
}
