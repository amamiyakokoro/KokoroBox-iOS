import Foundation

public actor KokoroPreloadStore {
    public static let shared = KokoroPreloadStore()

    private struct Entry<Value: Sendable>: Sendable {
        let value: Value
        let loadedAt: Date
    }

    typealias UserLoader = @Sendable () async throws -> KokoroUser
    typealias SubscriptionOptionsLoader = @Sendable () async throws -> KokoroSubscriptionOptions
    typealias RulesLoader = @Sendable () async throws -> KokoroCustomRulesState
    typealias RuleOptionsLoader = @Sendable () async throws -> KokoroCustomRulesOptions
    typealias SessionLoader = @Sendable () async -> Bool

    private let freshnessInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let sessionLoader: SessionLoader
    private let userLoader: UserLoader
    private let subscriptionOptionsLoader: SubscriptionOptionsLoader
    private let rulesLoader: RulesLoader
    private let ruleOptionsLoader: RuleOptionsLoader

    private var userEntry: Entry<KokoroUser>?
    private var subscriptionOptionsEntry: Entry<KokoroSubscriptionOptions>?
    private var rulesEntry: Entry<KokoroCustomRulesState>?
    private var ruleOptionsEntry: Entry<KokoroCustomRulesOptions>?

    private var userTask: Task<KokoroUser, Error>?
    private var subscriptionOptionsTask: Task<KokoroSubscriptionOptions, Error>?
    private var rulesTask: Task<KokoroCustomRulesState, Error>?
    private var ruleOptionsTask: Task<KokoroCustomRulesOptions, Error>?
    private var userGeneration = 0
    private var subscriptionOptionsGeneration = 0
    private var rulesGeneration = 0
    private var ruleOptionsGeneration = 0

    private init() {
        freshnessInterval = 300
        now = { Date() }
        sessionLoader = { await KokoroSession.shared.hasSession() }
        userLoader = { try await KokoroAPI.currentUser() }
        subscriptionOptionsLoader = { try await KokoroAPI.subscriptionOptions() }
        rulesLoader = { try await KokoroAPI.customRules() }
        ruleOptionsLoader = { try await KokoroAPI.customRulesOptions() }
    }

    init(
        freshnessInterval: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = { Date() },
        sessionLoader: @escaping SessionLoader,
        userLoader: @escaping UserLoader,
        subscriptionOptionsLoader: @escaping SubscriptionOptionsLoader,
        rulesLoader: @escaping RulesLoader,
        ruleOptionsLoader: @escaping RuleOptionsLoader
    ) {
        self.freshnessInterval = freshnessInterval
        self.now = now
        self.sessionLoader = sessionLoader
        self.userLoader = userLoader
        self.subscriptionOptionsLoader = subscriptionOptionsLoader
        self.rulesLoader = rulesLoader
        self.ruleOptionsLoader = ruleOptionsLoader
    }

    public func preloadIfNeeded() async {
        guard await sessionLoader() else {
            invalidateAll()
            return
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [self] in _ = try? await currentUser() }
            group.addTask { [self] in _ = try? await subscriptionOptions() }
            group.addTask { [self] in _ = try? await customRules() }
            group.addTask { [self] in _ = try? await customRuleOptions() }
        }
    }

    public func currentUser(forceRefresh: Bool = false) async throws -> KokoroUser {
        if !forceRefresh, let userEntry, isFresh(userEntry.loadedAt) {
            return userEntry.value
        }
        if let userTask { return try await userTask.value }
        let loader = userLoader
        let expectedGeneration = userGeneration
        let task = Task { try await loader() }
        userTask = task
        do {
            let value = try await task.value
            if userGeneration == expectedGeneration {
                userTask = nil
                userEntry = Entry(value: value, loadedAt: now())
            }
            return value
        } catch {
            if userGeneration == expectedGeneration { userTask = nil }
            throw error
        }
    }

    public func subscriptionOptions(forceRefresh: Bool = false) async throws -> KokoroSubscriptionOptions {
        if !forceRefresh, let subscriptionOptionsEntry, isFresh(subscriptionOptionsEntry.loadedAt) {
            return subscriptionOptionsEntry.value
        }
        if let subscriptionOptionsTask { return try await subscriptionOptionsTask.value }
        let loader = subscriptionOptionsLoader
        let expectedGeneration = subscriptionOptionsGeneration
        let task = Task { try await loader() }
        subscriptionOptionsTask = task
        do {
            let value = try await task.value
            if subscriptionOptionsGeneration == expectedGeneration {
                subscriptionOptionsTask = nil
                subscriptionOptionsEntry = Entry(value: value, loadedAt: now())
            }
            return value
        } catch {
            if subscriptionOptionsGeneration == expectedGeneration { subscriptionOptionsTask = nil }
            throw error
        }
    }

    public func customRules(forceRefresh: Bool = false) async throws -> KokoroCustomRulesState {
        if !forceRefresh, let rulesEntry, isFresh(rulesEntry.loadedAt) {
            return rulesEntry.value
        }
        if let rulesTask { return try await rulesTask.value }
        let loader = rulesLoader
        let expectedGeneration = rulesGeneration
        let task = Task { try await loader() }
        rulesTask = task
        do {
            let value = try await task.value
            if rulesGeneration == expectedGeneration {
                rulesTask = nil
                rulesEntry = Entry(value: value, loadedAt: now())
            }
            return value
        } catch {
            if rulesGeneration == expectedGeneration { rulesTask = nil }
            throw error
        }
    }

    public func customRuleOptions(forceRefresh: Bool = false) async throws -> KokoroCustomRulesOptions {
        if !forceRefresh, let ruleOptionsEntry, isFresh(ruleOptionsEntry.loadedAt) {
            return ruleOptionsEntry.value
        }
        if let ruleOptionsTask { return try await ruleOptionsTask.value }
        let loader = ruleOptionsLoader
        let expectedGeneration = ruleOptionsGeneration
        let task = Task { try await loader() }
        ruleOptionsTask = task
        do {
            let value = try await task.value
            if ruleOptionsGeneration == expectedGeneration {
                ruleOptionsTask = nil
                ruleOptionsEntry = Entry(value: value, loadedAt: now())
            }
            return value
        } catch {
            if ruleOptionsGeneration == expectedGeneration { ruleOptionsTask = nil }
            throw error
        }
    }

    public func invalidateCustomRuleState() {
        rulesGeneration += 1
        rulesEntry = nil
        rulesTask?.cancel()
        rulesTask = nil
    }

    public func invalidateAll() {
        userGeneration += 1
        subscriptionOptionsGeneration += 1
        rulesGeneration += 1
        ruleOptionsGeneration += 1
        userEntry = nil
        subscriptionOptionsEntry = nil
        rulesEntry = nil
        ruleOptionsEntry = nil
        userTask?.cancel()
        subscriptionOptionsTask?.cancel()
        rulesTask?.cancel()
        ruleOptionsTask?.cancel()
        userTask = nil
        subscriptionOptionsTask = nil
        rulesTask = nil
        ruleOptionsTask = nil
    }

    private func isFresh(_ loadedAt: Date) -> Bool {
        loadedAt.addingTimeInterval(freshnessInterval) > now()
    }
}
