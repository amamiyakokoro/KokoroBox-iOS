// swift-tools-version: 5.9
import PackageDescription

// Tests compile the production OAuth and token session independently of Libbox/Xcode signing.
let package = Package(
    name: "KokoroAuthTests",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "KokoroAuth", path: "Library/Network", exclude: [
            "BridgeTunTracker.swift",
            "CommandClient.swift",
            "CommandTarget.swift",
            "CommandXPC.swift",
            "ConnectionOwnerLookup.swift",
            "Extension+Iterator.swift",
            "Extension+RunBlocking.swift",
            "ExtensionEnvironments.swift",
            "ExtensionErrors.swift",
            "ExtensionPlatformInterface.swift",
            "ExtensionProfile.swift",
            "ExtensionProvider.swift",
            "ExtensionStartOptions.swift",
            "HTTPClient.swift",
            "HelperServiceManager.swift",
            "JailbreakHelperManager.swift",
            "MachServiceClient.swift",
            "NEVPNStatus+isConnected.swift",
            "OnDemandRule.swift",
            "OutboundGroup.swift",
            "RootHelperXPC.swift",
            "ShellHelperXPC.swift",
            "ShellSessionManager.swift",
            "SystemExtension.swift",
            "TaildropSendSession.swift",
            "TaildropTargets.swift",
            "UserServiceEndpointPublisher.swift",
            "UserServiceEndpointRegistry.swift",
            "UserServiceXPC.swift",
            "XPCMachServiceBridge.swift",
        ], sources: ["KokoroAPI.swift", "KokoroOAuth.swift"]),
        .target(name: "KokoroWebAuth", dependencies: ["KokoroAuth"], path: "ApplicationLibrary/Service", exclude: [
            "NWSocket.swift",
            "ProfileServer.swift",
            "ProfileUpdateTask.swift",
            "ReportTransfer.swift",
            "ReportTransferServer.swift",
            "UIProfileUpdateTask.swift",
            "UpdateManager.swift",
        ], sources: ["KokoroWebAuthenticator.swift"]),
        .testTarget(name: "KokoroAuthTests", dependencies: ["KokoroAuth", "KokoroWebAuth"], path: "Tests/KokoroAuthTests"),
    ]
)
