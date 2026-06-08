import ComposableArchitecture
import Foundation
import SQLiteData
import SwiftUI

/// Root feature: lists the user's vaults and supports creating and deleting them.
///
/// Reads flow through `@FetchAll`, which observes the SQLite database (and thus
/// reflects iCloud sync automatically). Writes go through the `defaultDatabase`
/// dependency so they can be controlled in tests.
@Reducer
public struct AppFeature {
    @ObservableState
    public struct State {
        @ObservationStateIgnored
        @FetchAll(Vault.order { $0.createdAt.desc() })
        public var vaults: [Vault]

        public init() {}
    }

    public enum Action {
        case addVaultButtonTapped
        case deleteVaults(IndexSet)
    }

    @Dependency(\.defaultDatabase) var database

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addVaultButtonTapped:
                return .run { _ in
                    try await database.write { db in
                        try Vault.insert { Vault.Draft(name: "New Vault") }.execute(db)
                    }
                }

            case let .deleteVaults(indexSet):
                let ids = indexSet.map { state.vaults[$0].id }
                return .run { _ in
                    try await database.write { db in
                        try Vault.where { $0.id.in(ids) }.delete().execute(db)
                    }
                }
            }
        }
    }
}

public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(store.vaults) { vault in
                    Text(vault.name.isEmpty ? "Untitled Vault" : vault.name)
                }
                .onDelete { store.send(.deleteVaults($0)) }
            }
            .navigationTitle("Vaults")
            .toolbar {
                Button {
                    store.send(.addVaultButtonTapped)
                } label: {
                    Label("Add Vault", systemImage: "plus")
                }
            }
            .overlay {
                if store.vaults.isEmpty {
                    ContentUnavailableView(
                        "No Vaults",
                        systemImage: "tray",
                        description: Text("Tap + to create your first vault.")
                    )
                }
            }
        }
    }
}
