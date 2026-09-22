import BackgroundTasks
import Foundation
import Library
#if canImport(UIKit)
    import UIKit
#endif

#if os(iOS) || os(tvOS)
    private final class BackgroundTaskCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false

        func finish(_ task: BGTask, success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
    }

    public class UIProfileUpdateTask: BGAppRefreshTask {
        private static let taskSchedulerPermittedIdentifier = AppConfiguration.backgroundTaskID

        private static var registered = false
        public static func configure() throws {
            if !registered {
                let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskSchedulerPermittedIdentifier, using: nil) { task in
                    NSLog("profile update task started")
                    Task {
                        await UIProfileUpdateTask.getAndUpdateProfiles(task)
                    }
                }
                if !success {
                    throw NSError(domain: "UIProfileUpdateTask", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Register task failed")])
                }
                registered = true
            }
            Task { @MainActor in
                await refreshAndSchedule()
            }
        }

        public static func applicationDidBecomeActive() {
            Task { @MainActor in
                await refreshAndSchedule()
            }
        }

        @MainActor
        private static func refreshAndSchedule() async {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskSchedulerPermittedIdentifier)
            _ = await ProfileUpdateTask.updateDueProfiles()
            do {
                try await ProfileUpdateTask.configure()
                let profiles = try await ProfileManager.listAutoUpdateEnabled()
                guard !profiles.isEmpty else { return }
                try scheduleUpdate(ProfileUpdateTask.calculateEarliestBeginDate(profiles))
            } catch {
                NSLog("schedule profile update task failed: \(error.localizedDescription)")
            }
        }

        private nonisolated static func getAndUpdateProfiles(_ task: BGTask) async {
            let completion = BackgroundTaskCompletion()
            let updateTask = Task {
                let success = await ProfileUpdateTask.updateDueProfiles()
                if !Task.isCancelled {
                    await rescheduleBackgroundUpdate()
                    completion.finish(task, success: success)
                }
            }
            task.expirationHandler = {
                updateTask.cancel()
                completion.finish(task, success: false)
                Task {
                    await rescheduleBackgroundUpdate()
                }
            }
            await updateTask.value
        }

        private nonisolated static func rescheduleBackgroundUpdate() async {
            do {
                let profiles = try await ProfileManager.listAutoUpdateEnabled()
                guard !profiles.isEmpty else { return }
                try scheduleUpdate(ProfileUpdateTask.calculateEarliestBeginDate(profiles))
            } catch {
                NSLog("reschedule profile update task failed: \(error.localizedDescription)")
            }
        }

        private static func scheduleUpdate(_ earliestBeginDate: Date?) throws {
            let request = BGAppRefreshTaskRequest(identifier: taskSchedulerPermittedIdentifier)
            request.earliestBeginDate = earliestBeginDate
            try BGTaskScheduler.shared.submit(request)
        }
    }
#endif
