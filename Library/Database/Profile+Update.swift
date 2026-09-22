import Foundation
import GRDB
import Libbox

private actor RemoteProfileUpdateCoordinator {
    static let shared = RemoteProfileUpdateCoordinator()

    private var updates: [Int64: Task<Void, Error>] = [:]

    func update(_ profile: Profile) async throws {
        guard let profileID = profile.id else {
            try await profile.performRemoteProfileUpdate()
            return
        }
        if let update = updates[profileID] {
            try await withTaskCancellationHandler {
                try await update.value
            } onCancel: {
                update.cancel()
            }
            return
        }
        let update = Task {
            try await profile.performRemoteProfileUpdate()
        }
        updates[profileID] = update
        defer { updates[profileID] = nil }
        try await withTaskCancellationHandler {
            try await update.value
        } onCancel: {
            update.cancel()
        }
    }
}

public extension Profile {
    nonisolated func updateRemoteProfile() async throws {
        try await RemoteProfileUpdateCoordinator.shared.update(self)
    }

    fileprivate nonisolated func performRemoteProfileUpdate() async throws {
        if type != .remote {
            return
        }
        let url = remoteURL
        let remoteContent: String
        if let url, KokoroAPI.isAuthenticatedConfigurationURL(url) {
            remoteContent = try await KokoroAPI.downloadConfiguration(from: url, userAgent: userAgent)
        } else {
            remoteContent = try await HTTPClient.getStringAsync(url, userAgent: userAgent)
        }
        try await BlockingIO.run {
            var error: NSError?
            LibboxCheckConfig(remoteContent, &error)
            if let error {
                throw error
            }
        }
        await MainActor.run {
            lastUpdated = Date()
        }
        try await ProfileManager.update(self)
        do {
            let oldContent = try await readAsync()
            if oldContent == remoteContent {
                return
            }
        } catch {}
        try await writeAsync(remoteContent)
        try await onProfileUpdated()
    }

    nonisolated func onProfileUpdated() async throws {
        if await SharedPreferences.selectedProfileID.get() == id {
            if let profile = try? await ExtensionProfile.load() {
                if await profile.status == .connected {
                    try await profile.reloadService()
                }
            }
        }
    }
}
