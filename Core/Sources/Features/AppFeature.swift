import ComposableArchitecture
import Foundation
import SQLiteData
import SwiftUI

/// Root feature: lists the user's vaults and supports creating and deleting them.
///
/// Reads flow through `@FetchAll`, which observes the SQLite database (and thus
/// reflects iCloud sync automatically). Writes go through the `defaultDatabase`
/// dependency so they can be controlled in tests. Write failures are surfaced to
/// the user as an alert rather than swallowed.
@Reducer
public struct AppFeature {
    @ObservableState
    public struct State {
        @ObservationStateIgnored
        @FetchAll(Vault.order { $0.createdAt.desc() })
        public var vaults: [Vault]

        @Presents public var alert: AlertState<Action.Alert>?

        public init() {}
    }

    public enum Action {
        case addVaultButtonTapped
        case alert(PresentationAction<Alert>)
        case deleteVaults(IndexSet)
        case operationFailed(String)

        public enum Alert {}
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addVaultButtonTapped:
                let database = database
                let now = now
                return .run { _ in
                    try await database.write { db in
                        try Vault.insert { Vault.Draft(name: "New Vault", createdAt: now) }
                            .execute(db)
                    }
                } catch: { error, send in
                    await send(.operationFailed(error.localizedDescription))
                }

            case .alert:
                return .none

            case let .deleteVaults(indexSet):
                let database = database
                let ids = indexSet.map { state.vaults[$0].id }
                return .run { _ in
                    try await database.write { db in
                        try Vault.where { $0.id.in(ids) }.delete().execute(db)
                    }
                } catch: { error, send in
                    await send(.operationFailed(error.localizedDescription))
                }

            case let .operationFailed(message):
                state.alert = AlertState {
                    TextState("Something Went Wrong")
                } actions: {
                    ButtonState(role: .cancel) { TextState("OK") }
                } message: {
                    TextState(message)
                }
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
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
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}
