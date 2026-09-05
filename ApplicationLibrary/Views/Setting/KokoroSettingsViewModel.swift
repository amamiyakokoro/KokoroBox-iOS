#if !os(tvOS)
    import Foundation
    import Library

    @MainActor
    final class KokoroSettingsViewModel: BaseViewModel {
        @Published private(set) var isSignedIn = false
        @Published private(set) var user: KokoroUser?

        private let authenticator = KokoroWebAuthenticator.shared
        private let preloadStore = KokoroPreloadStore.shared
        private var signInTask: Task<Void, Error>?
        private var didLoad = false

        func loadIfNeeded() async {
            guard !didLoad else { return }
            didLoad = true
            guard await KokoroSession.shared.hasSession() else { return }
            await loadAccount(forceRefresh: false)
        }

        func reload() async {
            await loadAccount(forceRefresh: true)
        }

        private func loadAccount(forceRefresh: Bool) async {
            isLoading = true
            defer { isLoading = false }
            do {
                user = try await preloadStore.currentUser(forceRefresh: forceRefresh)
                isSignedIn = true
            } catch {
                isSignedIn = await KokoroSession.shared.hasSession()
                alert = AlertState(action: String(localized: "load Kokoro account"), error: error)
            }
        }

        func signIn() async {
            guard signInTask == nil else { return }
            isLoading = true
            defer { isLoading = false; signInTask = nil }
            do {
                let task = Task { try await authenticator.signIn() }
                signInTask = task
                try await task.value
                await preloadStore.invalidateAll()
                user = try await preloadStore.currentUser(forceRefresh: true)
                isSignedIn = true
            } catch is CancellationError {
                return
            } catch {
                isSignedIn = await KokoroSession.shared.hasSession()
                if isSignedIn {
                    alert = AlertState(action: String(localized: "load Kokoro account"), error: error)
                } else {
                    alert = AlertState(
                        errorMessage: "\(String(localized: "Failed to sign in to Kokoro"))\n\(error.localizedDescription)"
                    )
                }
            }
        }

        func signOut() async {
            isLoading = true
            await KokoroSession.shared.revoke()
            await preloadStore.invalidateAll()
            user = nil
            isSignedIn = false
            isLoading = false
        }

        func cancelSignIn() {
            signInTask?.cancel()
        }
    }
#endif
