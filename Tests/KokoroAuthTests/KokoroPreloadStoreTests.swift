import XCTest
@testable import KokoroAuth

final class KokoroPreloadStoreTests: XCTestCase {
    private actor Counter {
        private(set) var value = 0

        func increment() -> Int {
            value += 1
            return value
        }
    }

    private enum TestError: Error {
        case unusedLoader
    }

    func testAccountPreloadIsSingleFlightCachedAndInvalidated() async throws {
        let counter = Counter()
        let store = KokoroPreloadStore(
            sessionLoader: { true },
            userLoader: {
                let call = await counter.increment()
                try await Task.sleep(nanoseconds: 20_000_000)
                return KokoroUser(
                    osuId: String(call),
                    username: "Kokoro",
                    avatarUrl: nil,
                    plans: ["Basic"],
                    plansDetails: [],
                    trafficUsage: 0,
                    bandwidthLimit: 0,
                    subscriptionExpiresAt: nil
                )
            },
            subscriptionOptionsLoader: { throw TestError.unusedLoader },
            rulesLoader: { throw TestError.unusedLoader },
            ruleOptionsLoader: { throw TestError.unusedLoader }
        )

        async let first = store.currentUser()
        async let second = store.currentUser()
        let firstPair = try await (first, second)
        XCTAssertEqual(firstPair.0.osuId, "1")
        XCTAssertEqual(firstPair.1.osuId, "1")
        var requestCount = await counter.value
        XCTAssertEqual(requestCount, 1)

        let cached = try await store.currentUser()
        XCTAssertEqual(cached.osuId, "1")
        requestCount = await counter.value
        XCTAssertEqual(requestCount, 1)

        await store.invalidateAll()
        let reloaded = try await store.currentUser()
        XCTAssertEqual(reloaded.osuId, "2")
        requestCount = await counter.value
        XCTAssertEqual(requestCount, 2)
    }

    func testPreloadDoesNotRequestDataWithoutSession() async {
        let counter = Counter()
        let store = KokoroPreloadStore(
            sessionLoader: { false },
            userLoader: {
                _ = await counter.increment()
                throw TestError.unusedLoader
            },
            subscriptionOptionsLoader: { throw TestError.unusedLoader },
            rulesLoader: { throw TestError.unusedLoader },
            ruleOptionsLoader: { throw TestError.unusedLoader }
        )

        await store.preloadIfNeeded()
        let requestCount = await counter.value
        XCTAssertEqual(requestCount, 0)
    }
}
