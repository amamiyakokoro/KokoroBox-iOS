#if !os(tvOS)
    import AuthenticationServices
    import Foundation
    #if SWIFT_PACKAGE
        import KokoroAuth
    #else
        import Library
    #endif
    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    @MainActor
    protocol KokoroBrowserSession: AnyObject {
        var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)? { get set }
        var prefersEphemeralWebBrowserSession: Bool { get set }
        func start() -> Bool
        func cancel()
    }

    extension ASWebAuthenticationSession: KokoroBrowserSession {}

    @MainActor
    public final class KokoroWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
        public static let shared = KokoroWebAuthenticator()
        private var authenticationSession: (any KokoroBrowserSession)?
        private var transaction = KokoroLoginTransaction()
        private var activeID: UUID?
        private var continuation: CheckedContinuation<KokoroAuthorization, Error>?
        private var expiryTask: Task<Void, Never>?
        private let makeSession: (URL, @escaping (URL?, Error?) -> Void) -> any KokoroBrowserSession
        private let exchange: (KokoroAuthorization) async throws -> Void
        private let lifetimeNanoseconds: UInt64

        init(
            makeSession: @escaping (URL, @escaping (URL?, Error?) -> Void) -> any KokoroBrowserSession = {
                ASWebAuthenticationSession(url: $0, callbackURLScheme: "kokoro", completionHandler: $1)
            },
            exchange: @escaping (KokoroAuthorization) async throws -> Void = {
                try await KokoroSession.shared.exchangeAuthorizationCode($0)
            },
            lifetimeNanoseconds: UInt64 = UInt64(KokoroPendingLogin.lifetime * 1_000_000_000)
        ) {
            self.makeSession = makeSession
            self.exchange = exchange
            self.lifetimeNanoseconds = lifetimeNanoseconds
            super.init()
        }

        func signIn() async throws {
            guard activeID == nil else { throw KokoroAuthenticationError.alreadyInProgress }
            try Task.checkCancellation()
            let id = UUID()
            let login = try transaction.begin()
            activeID = id
            defer { cleanup(id: id) }
            let loginURL = try login.loginURL()
            try await withTaskCancellationHandler {
                let authorization = try await callback(from: loginURL, id: id)
                try Task.checkCancellation()
                try await exchange(authorization)
            } onCancel: {
                Task { @MainActor in
                    self.finish(.failure(CancellationError()), id: id)
                }
            }
        }

        /// Called by both warm and cold onOpenURL delivery, before profile import/error handling.
        /// After a process restart there is no verifier; reject and ask for a new login.
        @discardableResult
        public func handleCallback(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "kokoro" else { return false }
            guard let id = activeID, continuation != nil else { return false }
            receive(url, id: id)
            return true
        }

        private func receive(_ url: URL, id: UUID) {
            guard activeID == id, continuation != nil else { return }
            do {
                finish(.success(try transaction.consume(url)), id: id)
            } catch {
                finish(.failure(error), id: id)
            }
        }

        private func callback(from loginURL: URL, id: UUID) async throws -> KokoroAuthorization {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = makeSession(loginURL) { [weak self] url, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                            self.finish(.failure(cancelled ? CancellationError() : KokoroAuthenticationError.couldNotStart), id: id)
                        } else if let url {
                            self.receive(url, id: id)
                        } else {
                            self.finish(.failure(KokoroAuthenticationError.invalidCallback), id: id)
                        }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                authenticationSession = session
                expiryTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: self?.lifetimeNanoseconds ?? 0) }
                    catch { return }
                    self?.finish(.failure(KokoroAuthenticationError.expired), id: id)
                }
                if !session.start() {
                    finish(.failure(KokoroAuthenticationError.couldNotStart), id: id)
                }
            }
        }

        private func finish(_ result: Result<KokoroAuthorization, Error>, id: UUID) {
            guard activeID == id, let continuation else { return }
            self.continuation = nil
            transaction.cancel()
            expiryTask?.cancel()
            expiryTask = nil
            let session = authenticationSession
            authenticationSession = nil
            session?.cancel()
            continuation.resume(with: result)
        }

        private func cleanup(id: UUID) {
            guard activeID == id else { return }
            finish(.failure(CancellationError()), id: id)
            transaction.cancel()
            activeID = nil
        }

        public func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
            #if os(iOS)
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                    ?? scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
            #elseif os(macOS)
                return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
            #endif
        }
    }
#endif
