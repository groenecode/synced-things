import CloudKit
import Dependencies
import SQLiteData

#if os(iOS)
    import UIKit

    /// Routes incoming CloudKit shares to the sync engine on iOS.
    final class AppDelegate: UIResponder, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            configurationForConnecting connectingSceneSession: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(
                name: "Default Configuration",
                sessionRole: connectingSceneSession.role
            )
            configuration.delegateClass = SceneDelegate.self
            return configuration
        }
    }

    final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
        @Dependency(\.defaultSyncEngine) var syncEngine

        func windowScene(
            _ windowScene: UIWindowScene,
            userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
        ) {
            Task { try await syncEngine.acceptShare(metadata: cloudKitShareMetadata) }
        }

        func scene(
            _ scene: UIScene,
            willConnectTo session: UISceneSession,
            options connectionOptions: UIScene.ConnectionOptions
        ) {
            guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
            Task { try await syncEngine.acceptShare(metadata: metadata) }
        }
    }
#elseif os(macOS)
    import AppKit

    /// Routes incoming CloudKit shares to the sync engine on macOS.
    final class MacAppDelegate: NSObject, NSApplicationDelegate {
        @Dependency(\.defaultSyncEngine) var syncEngine

        func application(
            _ application: NSApplication,
            userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
        ) {
            Task { try await syncEngine.acceptShare(metadata: metadata) }
        }
    }
#endif
