import ComposableArchitecture
import SQLiteData
import SwiftUI

/// Create/edit form for a ``Thing``. The same reducer and view back both modes:
/// a fresh `Thing.Draft` (no `id`) means create, an existing thing's draft means
/// edit. The form owns its own save (`upsert`) and dismisses itself on success;
/// write failures are surfaced as an alert and the sheet stays open.
@Reducer
public struct ThingFormFeature {
    @ObservableState
    public struct State: Equatable {
        @Presents public var alert: AlertState<Action.Alert>?
        public var draft: Thing.Draft

        /// Create mode: a draft seeded with its parent `vaultID` (and the
        /// position the parent picked for it), but no `id`.
        public init(draft: Thing.Draft) {
            self.draft = draft
        }

        /// Edit mode: a draft seeded from an existing thing (carries its `id`).
        public init(thing: Thing) {
            self.draft = Thing.Draft(thing)
        }

        public var isEditing: Bool { draft.id != nil }

        public var isSaveDisabled: Bool {
            draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                // Pass the whole draft through to `upsert` (rather than
                // rebuilding it field-by-field) so columns added to `Thing`
                // later are never silently dropped on save. Persist the trimmed
                // text so what we validated (see `isSaveDisabled`) is what we
                // store, and stamp `updatedAt` on every save.
                var draft = state.draft
                draft.text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.updatedAt = now
                let savedDraft = draft
                let database = database
                let dismiss = dismiss
                return .run { _ in
                    try await database.write { db in
                        try Thing.upsert { savedDraft }.execute(db)
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

public struct ThingFormView: View {
    @Bindable var store: StoreOf<ThingFormFeature>

    public init(store: StoreOf<ThingFormFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("Text", text: $store.draft.text, axis: .vertical)
            }
            .navigationTitle(store.isEditing ? "Edit Thing" : "New Thing")
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
