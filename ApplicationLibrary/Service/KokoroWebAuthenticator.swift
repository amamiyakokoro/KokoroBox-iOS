#if !os(tvOS)
    import AuthenticationServices
    import Foundation
    import Library
    import Security
    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    enum KokoroAuthenticationError: LocalizedError {
        case alreadyInProgress
        case couldNotStart
        case invalidCallback
        case stateMismatch
        case accessDenied
        case server(String)

        var errorDescription: String? {
            switch self {
            case .alreadyInProgress:
                return String(localized: "A Kokoro sign-in is already in progress.")
            case .couldNotStart:
                return String(localized: "Could not open the Kokoro sign-in page.")
            case .invalidCallback:
                return String(localized: "Kokoro returned an invalid sign-in callback.")
            case .stateMismatch:
                return String(localized: "Kokoro sign-in could not be verified. Please try again.")
            case .accessDenied:
                return String(localized: "Kokoro sign-in was denied or this account is not authorized.")
            case let .server(message):
                return String(localized: "Kokoro sign-in failed: \(message)")
            }
        }
    }

    @MainActor
    final class KokoroWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
        private var authenticationSession: ASWebAuthenticationSession?

        func signIn() async throws {
            guard authenticationSession == nil else {
                throw KokoroAuthenticationError.alreadyInProgress
            }
            let state = try Self.randomState()
            let loginURL = try KokoroAPI.loginURL(state: state)
            let callbackURL = try await callback(from: loginURL)
            let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
            try await KokoroSession.shared.exchangeAuthorizationCode(code)
        }

        private func callback(from loginURL: URL) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: loginURL, callbackURLScheme: "kokoro") { [weak self] callbackURL, error in
                    Task { @MainActor in
                        self?.authenticationSession = nil
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let callbackURL {
                            continuation.resume(returning: callbackURL)
                        } else {
                            continuation.resume(throwing: KokoroAuthenticationError.invalidCallback)
                        }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                authenticationSession = session
                if !session.start() {
                    authenticationSession = nil
                    continuation.resume(throwing: KokoroAuthenticationError.couldNotStart)
                }
            }
        }

        func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
            #if os(iOS)
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first {
                    return window
                }
                return ASPresentationAnchor()
            #elseif os(macOS)
                return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
            #endif
        }

        private static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
            guard callbackURL.scheme?.lowercased() == "kokoro",
                  callbackURL.host?.lowercased() == "oauth",
                  callbackURL.path == "/callback",
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            else {
                throw KokoroAuthenticationError.invalidCallback
            }

            let states = components.queryItems?.filter { $0.name == "state" }.compactMap(\.value) ?? []
            guard states.count == 1, constantTimeEqual(states[0], expectedState) else {
                throw KokoroAuthenticationError.stateMismatch
            }

            if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
                if error == "access_denied" {
                    throw KokoroAuthenticationError.accessDenied
                }
                throw KokoroAuthenticationError.server(error)
            }

            let codes = components.queryItems?.filter { $0.name == "code" }.compactMap(\.value) ?? []
            guard codes.count == 1, !codes[0].isEmpty else {
                throw KokoroAuthenticationError.invalidCallback
            }
            return codes[0]
        }

        private static func randomState() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                throw KokoroAPIError.keychain(status: status)
            }
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
            let lhsBytes = Array(lhs.utf8)
            let rhsBytes = Array(rhs.utf8)
            var difference = lhsBytes.count ^ rhsBytes.count
            for index in 0 ..< max(lhsBytes.count, rhsBytes.count) {
                let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
                let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
                difference |= Int(lhsByte ^ rhsByte)
            }
            return difference == 0
        }
    }
#endif
