import Foundation
import GRDB
import Libbox

private actor RemoteProfileUpdateCoordinator {
    static let shared = RemoteProfileUpdateCoordinator()

    private struct Update {
        let identifier: UUID
        let task: Task<Void, Error>
    }

    private var updates: [Int64: Update] = [:]

    func update(_ profile: Profile, forceRefresh: Bool = false) async throws {
        guard let profileID = profile.id else {
            try await profile.performRemoteProfileUpdate()
            return
        }
        if let update = updates[profileID], !forceRefresh {
            try await withTaskCancellationHandler {
                try await update.task.value
            } onCancel: {
                update.task.cancel()
            }
            return
        }
        let previous = updates[profileID]?.task
        let identifier = UUID()
        let update = Task {
            // A rule-triggered refresh must download after any older in-flight update finishes.
            if let previous { _ = try? await previous.value }
            try Task.checkCancellation()
            try await profile.performRemoteProfileUpdate()
        }
        updates[profileID] = Update(identifier: identifier, task: update)
        defer {
            if updates[profileID]?.identifier == identifier { updates[profileID] = nil }
        }
        try await withTaskCancellationHandler {
            try await update.value
        } onCancel: {
            update.cancel()
        }
    }
}

public extension Profile {
    nonisolated func updateRemoteProfile(forceRefresh: Bool = false) async throws {
        try await RemoteProfileUpdateCoordinator.shared.update(self, forceRefresh: forceRefresh)
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
