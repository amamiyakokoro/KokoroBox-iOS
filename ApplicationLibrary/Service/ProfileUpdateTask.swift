import Foundation
import Library

public enum ProfileUpdateTask {
    static let minUpdateInterval: TimeInterval = 15 * 60
    static let defaultUpdateInterval: TimeInterval = 60 * 60

    private static var timer: Timer?

    public static func configure() async throws {
        let profiles = try await ProfileManager.listAutoUpdateEnabled()
        await MainActor.run {
            timer?.invalidate()
            timer = nil
            guard !profiles.isEmpty else {
                return
            }
            let updateInterval = max(
                profiles.map(\.autoUpdateIntervalOrDefault).min() ?? defaultUpdateInterval,
                minUpdateInterval
            )
            let newTimer = Timer(fire: calculateEarliestBeginDate(profiles), interval: updateInterval, repeats: true) { _ in
                Task {
                    await updateDueProfiles()
                }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        }
    }

    static func calculateEarliestBeginDate(_ profiles: [Profile]) -> Date {
        let nowTime = Date.now
        var earliestBeginDate = profiles.map { profile in
            guard let lastUpdated = profile.lastUpdated else {
                return nowTime
            }
            return lastUpdated.addingTimeInterval(profile.autoUpdateIntervalOrDefault)
        }.min() ?? nowTime
        if earliestBeginDate <= nowTime {
            earliestBeginDate = nowTime
        }
        return earliestBeginDate
    }

    @discardableResult
    public nonisolated static func updateDueProfiles() async -> Bool {
        do {
            let success = await updateProfiles(try await ProfileManager.listAutoUpdateEnabled())
            NSLog("profile update task succeed")
            return success
        } catch {
            NSLog("profile update task failed: \(error.localizedDescription)")
            return false
        }
    }

    static func updateProfiles(_ profiles: [Profile]) async -> Bool {
        var success = true
        for profile in profiles {
            if Task.isCancelled {
                return false
            }
            let profileName = profile.name
            if let lastUpdated = profile.lastUpdated,
               lastUpdated > Date(timeIntervalSinceNow: -profile.autoUpdateIntervalOrDefault)
            {
                continue
            }
            do {
                try await profile.updateRemoteProfile()
                NSLog("Updated profile %@", profileName)
            } catch {
                NSLog("Update profile %@ failed: %@", profileName, error.localizedDescription)
                success = false
            }
        }
        return success
    }
}

extension Profile {
    var autoUpdateIntervalOrDefault: TimeInterval {
        if autoUpdateInterval > 0 {
            return TimeInterval(autoUpdateInterval * 60)
        } else {
            return ProfileUpdateTask.defaultUpdateInterval
        }
    }
}
