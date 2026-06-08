import ComposableArchitecture
import SwiftUI
import SyncThingsCore

@main
struct SyncThingsApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    /// Created lazily on first access (inside `body`), after `init()` has
    /// bootstrapped the database and sync engine.
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        try! prepareDependencies {
            try $0.bootstrapDatabase()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
        }
    }
}
