import AppIntents
import SwiftUI
import WidgetKit

struct DashboardEntry: TimelineEntry {
    let date: Date
    var isStarted = false
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
        date: .now, isStarted: true, profileName: "Kokoro", mode: "rule",
        groupName: "Kokoro", selectedOutbound: "Hong Kong ANYTLS",
        download: "399 KB", upload: "277 KB", downloadSpeed: "1.5 KB/s",
        uploadSpeed: "0 KB/s", connections: "19", memory: "19 MB", updatedAt: .now
    )

    static var stoppedPreview: DashboardEntry {
        var entry = preview
        entry.isStarted = false
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
            completion(Timeline(entries: [value], policy: .after(Date().addingTimeInterval(900))))
        }
    }

    private func entry() async -> DashboardEntry {
        var value = DashboardEntry(date: .now)
        value.isStarted = (try? await WidgetTunnelControl.currentIsStarted()) ?? false
        let snapshot = UserDefaults(suiteName: WidgetAppConfiguration.appGroupID)?
            .dictionary(forKey: "dashboard_widget_snapshot") ?? [:]
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
        VStack(alignment: .leading, spacing: 5) {
            Text("Proxy")
                .font(.system(size: 19, weight: .semibold))
            Text(entry.groupName.isEmpty ? entry.profileName : entry.groupName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(entry.selectedOutbound.isEmpty ? String(localized: "Open app to view groups") : entry.selectedOutbound)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text("Selected proxy"))
                .accessibilityValue(entry.selectedOutbound.isEmpty ? String(localized: "No proxy data") : entry.selectedOutbound)

            Spacer(minLength: 0)

            HStack {
                Toggle(isOn: entry.isStarted, intent: ToggleServiceControlIntent()) {
                    Text("VPN")
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.green)
                .fixedSize()
                .accessibilityLabel("VPN service")

                Spacer(minLength: 0)

                Button(intent: RefreshDashboardIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update subscription")
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
                    Text(entry.profileName)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(entry.isStarted ? (entry.mode.isEmpty ? "RUNNING" : entry.mode.uppercased()) : "STOPPED")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Button(intent: RefreshDashboardIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update subscription")
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

            HStack(spacing: 0) {
                shortcut("Profile", icon: "doc.text", page: "dashboard")
                shortcut("Connections", icon: "link", page: "connections")
                shortcut("Kokoro", icon: "person.crop.circle.badge.checkmark", page: "kokoro")
                Toggle(isOn: entry.isStarted, intent: ToggleServiceControlIntent()) {
                    Text("VPN")
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.green)
                .fixedSize()
                .accessibilityLabel("VPN service")
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white.opacity(0.85))
        .widgetURL(URL(string: "sing-box://widget?page=dashboard"))
    }

    private func metric(_ symbol: String, _ value: String, label: LocalizedStringKey) -> some View {
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

    private func shortcut(_ title: LocalizedStringKey, icon: String, page: String) -> some View {
        Link(destination: URL(string: "sing-box://widget?page=\(page)")!) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
    }
}

struct RefreshDashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Update subscription"

    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(URL(string: "sing-box://widget?page=update-profile")!))
    }
}

#Preview(as: .systemMedium) {
    DashboardWidget()
} timeline: {
    DashboardEntry.preview
    DashboardEntry.stoppedPreview
}

#Preview(as: .systemSmall) {
    DashboardWidget()
} timeline: {
    DashboardEntry.preview
    DashboardEntry.stoppedPreview
}
