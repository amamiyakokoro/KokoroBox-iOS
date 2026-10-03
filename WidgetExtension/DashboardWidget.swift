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
        date: .now, isStarted: true, profileName: "[V1X1 🇭🇰]-香港 A_1", mode: "rule",
        groupName: "SR_CNIP", selectedOutbound: "TOKO-LAPIS-DIRECT",
        download: "1.7 TB", upload: "346.43 GB", downloadSpeed: "12.8 MB/s",
        uploadSpeed: "824 KB/s", connections: "18", memory: "178.11 MB", updatedAt: .now
    )
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
        .description("Profile, traffic snapshot and VPN controls.")
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
            HStack(alignment: .firstTextBaseline) {
                Text("Proxy")
                    .font(.system(size: 19, weight: .semibold))
                Spacer(minLength: 0)
                if !entry.selectedOutbound.isEmpty {
                    Text("Snapshot")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
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
                .accessibilityLabel(Text("Selected proxy snapshot"))
                .accessibilityValue(entry.selectedOutbound.isEmpty ? String(localized: "No proxy snapshot") : entry.selectedOutbound)

            Spacer(minLength: 0)

            HStack {
                Toggle(isOn: entry.isStarted, intent: ToggleServiceControlIntent()) {
                    Text("VPN")
                }
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
                .accessibilityLabel("Refresh VPN status")
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .widgetURL(URL(string: "sing-box://widget?page=groups"))
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
                    HStack(spacing: 5) {
                        Text(entry.isStarted ? (entry.mode.isEmpty ? "RUNNING" : entry.mode.uppercased()) : "STOPPED")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 0)
                        if let date = entry.updatedAt {
                            Text("Snapshot")
                                .font(.system(size: 9))
                            Text(date, style: .relative)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityLabel(Text("Snapshot updated at \(date.formatted())"))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                Button(intent: RefreshDashboardIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh VPN status")
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    metric("arrow.down", entry.download, label: "Downloaded")
                    metric("arrow.up", entry.upload, label: "Uploaded")
                    metric("link", entry.connections, label: "Outbound connections")
                }
                GridRow {
                    metric("arrow.down.circle", entry.downloadSpeed, label: "Download speed snapshot")
                    metric("arrow.up.circle", entry.uploadSpeed, label: "Upload speed snapshot")
                    metric("memorychip", entry.memory, label: "Memory snapshot")
                }
            }
            .foregroundStyle(.white.opacity(0.65))

            HStack(spacing: 0) {
                shortcut("Profile", page: "dashboard")
                shortcut("Groups", page: "groups")
                shortcut("Connections", page: "connections")
                shortcut("Tools", page: "tools")
                Toggle(isOn: entry.isStarted, intent: ToggleServiceControlIntent()) {
                    Text("VPN")
                }
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

    private func shortcut(_ title: LocalizedStringKey, page: String) -> some View {
        Link(destination: URL(string: "sing-box://widget?page=\(page)")!) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
    }
}

struct RefreshDashboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh VPN status"

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "\(WidgetAppConfiguration.packageName).widget.Dashboard")
        return .result()
    }
}

#Preview(as: .systemMedium) {
    DashboardWidget()
} timeline: {
    DashboardEntry.preview
    DashboardEntry(date: .now)
}

#Preview(as: .systemSmall) {
    DashboardWidget()
} timeline: {
    DashboardEntry.preview
    DashboardEntry(date: .now)
}
