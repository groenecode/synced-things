import ComposableArchitecture
import SQLiteData
import SwiftUI

/// Create/edit form for a ``Vault``. The same reducer and view back both modes:
/// a fresh `Vault.Draft` (no `id`) means create, an existing vault's draft means
/// edit. The form owns its own save (`upsert`) and dismisses itself on success;
/// write failures are surfaced as an alert and the sheet stays open.
@Reducer
public struct VaultFormFeature {
    @ObservableState
    public struct State: Equatable {
        @Presents public var alert: AlertState<Action.Alert>?
        public var draft: Vault.Draft

        /// Create mode: an empty draft with no `id`.
        public init(draft: Vault.Draft = Vault.Draft()) {
            self.draft = draft
        }

        /// Edit mode: a draft seeded from an existing vault (carries its `id`).
        public init(vault: Vault) {
            self.draft = Vault.Draft(vault)
        }

        public var isEditing: Bool { draft.id != nil }

        public var isSaveDisabled: Bool {
            draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public enum Action: BindableAction {
        case alert(PresentationAction<Alert>)
        case binding(BindingAction<State>)
        case cancelButtonTapped
        case saveButtonTapped
        case saveFailed(String)

        public enum Alert: Equatable {}
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .alert:
                return .none

            case .binding:
                return .none

            case .cancelButtonTapped:
                let dismiss = dismiss
                return .run { _ in await dismiss() }

            case .saveButtonTapped:
                guard !state.isSaveDisabled else { return .none }
                // Capture Sendable primitives and rebuild the draft inside the
                // effect; stamp `createdAt` from the clock only when creating.
                let id = state.draft.id
                // Persist the trimmed name so what we validated (see
                // `isSaveDisabled`) is what we store — no stray surrounding
                // whitespace, and a blank cell falls back to "Untitled Vault".
                let name = state.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let createdAt = id == nil ? now : state.draft.createdAt
                let database = database
                let dismiss = dismiss
                return .run { _ in
                    try await database.write { db in
                        try Vault.upsert {
                            Vault.Draft(id: id, name: name, createdAt: createdAt)
                        }
                        .execute(db)
                    }
                    await dismiss()
                } catch: { error, send in
                    await send(.saveFailed(error.localizedDescription))
                }

            case let .saveFailed(message):
                state.alert = .operationFailed(message)
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

public struct VaultFormView: View {
    @Bindable var store: StoreOf<VaultFormFeature>

    public init(store: StoreOf<VaultFormFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $store.draft.name)
            }
            .navigationTitle(store.isEditing ? "Edit Vault" : "New Vault")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.cancelButtonTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.saveButtonTapped) }
                        .disabled(store.isSaveDisabled)
                }
            }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }
}
