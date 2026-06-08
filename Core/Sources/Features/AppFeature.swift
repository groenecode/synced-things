import ComposableArchitecture
import Foundation
import SQLiteData
import SwiftUI

/// Root feature: lists the user's vaults and drives create/edit/delete.
///
/// Reads flow through `@FetchAll`, which observes the SQLite database (and thus
/// reflects iCloud sync automatically), so the list refreshes itself after any
/// write. Create and edit are handled by a presented ``VaultFormFeature``;
/// delete is confirmed with an alert and performed here. Write failures are
/// surfaced to the user as an alert rather than swallowed.
@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        @ObservationStateIgnored
        @FetchAll(Vault.order { $0.createdAt.desc() })
        public var vaults: [Vault]

        @Presents public var destination: Destination.State?

        public init() {}
    }

    public enum Action {
        case addButtonTapped
        case deleteButtonTapped(Vault)
        case destination(PresentationAction<Destination.Action>)
        case editButtonTapped(Vault)
        case operationFailed(String)
    }

    @Reducer
    public enum Destination {
        case alert(AlertState<Alert>)
        case form(VaultFormFeature)

        @CasePathable
        public enum Alert: Equatable {
            case confirmDelete(Vault.ID)
        }
    }

    @Dependency(\.defaultDatabase) var database

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.destination = .form(VaultFormFeature.State())
                return .none

            case let .deleteButtonTapped(vault):
                state.destination = .alert(.confirmDelete(vault))
                return .none

            case let .destination(.presented(.alert(.confirmDelete(id)))):
                let database = database
                return .run { _ in
                    try await database.write { db in
                        try Vault.where { $0.id.eq(id) }.delete().execute(db)
                    }
                } catch: { error, send in
                    await send(.operationFailed(error.localizedDescription))
                }

            case .destination:
                return .none

            case let .editButtonTapped(vault):
                state.destination = .form(VaultFormFeature.State(vault: vault))
                return .none

            case let .operationFailed(message):
                state.destination = .alert(.operationFailed(message))
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension AppFeature.Destination.State: Equatable {}

extension AlertState where Action == AppFeature.Destination.Alert {
    /// Delete confirmation. The alert's Delete button uses `role: .destructive`
    /// (standard red alert button); the *swipe* delete button is plain + red.
    static func confirmDelete(_ vault: Vault) -> Self {
        AlertState {
            TextState("Delete Vault?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmDelete(vault.id)) {
                TextState("Delete")
            }
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            let name = vault.name.isEmpty ? "Untitled Vault" : vault.name
            return TextState("\u{201C}\(name)\u{201D} and everything in it will be deleted.")
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Plain button tinted red — intentionally NOT
                            // `role: .destructive`. Full swipe is disabled so it
                            // can't bypass the confirmation alert.
                            Button("Delete") {
                                store.send(.deleteButtonTapped(vault))
                            }
                            .tint(.red)
                            Button("Edit") {
                                store.send(.editButtonTapped(vault))
                            }
                            .tint(.blue)
                        }
                }
            }
            .navigationTitle("Vaults")
            .toolbar {
                Button {
                    store.send(.addButtonTapped)
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
            .sheet(
                item: $store.scope(state: \.destination?.form, action: \.destination.form)
            ) { formStore in
                VaultFormView(store: formStore)
            }
            .alert(
                $store.scope(state: \.destination?.alert, action: \.destination.alert)
            )
        }
    }
}
