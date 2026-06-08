import CloudKit
import ComposableArchitecture
import Foundation
import SQLiteData
import SwiftUI

/// Detail feature: lists the ``Thing``s belonging to a single ``Vault`` and
/// drives create/edit/delete, mirroring ``AppFeature``.
///
/// The `@FetchAll` query is scoped to this vault and ordered by `position`, and
/// it observes the SQLite database (and thus iCloud sync), so the list refreshes
/// itself after any write. Create and edit are handled by a presented
/// ``ThingFormFeature``; delete is confirmed with an alert and performed here.
/// Write failures are surfaced to the user as an alert rather than swallowed.
@Reducer
public struct VaultDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public let vault: Vault

        @ObservationStateIgnored
        @FetchAll public var things: [Thing]

        @Presents public var destination: Destination.State?

        /// The CloudKit share for this vault, set once ``Action/shareButtonTapped``
        /// succeeds. Non-nil drives presentation of `CloudSharingView`, Apple's
        /// participant-management sheet. Sharing UI is iOS/iPadOS only — on native
        /// macOS the share button is hidden, so this simply stays `nil` there.
        public var sharedRecord: SharedRecord?

        public init(vault: Vault) {
            self.vault = vault
            // `id` is the tie-breaker: concurrent inserts can yield equal ranks,
            // and we want a stable, deterministic order regardless.
            _things = FetchAll(
                Thing.where { $0.vaultID.eq(vault.id) }.order { ($0.rank, $0.id) }
            )
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteButtonTapped(Thing)
        case destination(PresentationAction<Destination.Action>)
        case editButtonTapped(Thing)
        case moved(IndexSet, Int)
        case operationFailed(String)
        case shareButtonTapped
        case shareDismissed
        case shareResponse(SharedRecord)
    }

    @Reducer
    public enum Destination {
        case alert(AlertState<Alert>)
        case form(ThingFormFeature)

        @CasePathable
        public enum Alert: Equatable {
            case confirmDelete(Thing.ID)
        }
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.defaultSyncEngine) var syncEngine

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                // Append to the end: generate a key after the last thing's rank
                // (`things` is sorted ascending), or the first key when empty.
                let nextRank = FractionalIndex.keyBetween(state.things.last?.rank, nil)
                state.destination = .form(
                    ThingFormFeature.State(
                        draft: Thing.Draft(vaultID: state.vault.id, rank: nextRank)
                    )
                )
                return .none

            case let .deleteButtonTapped(thing):
                state.destination = .alert(.confirmDelete(thing))
                return .none

            case let .destination(.presented(.alert(.confirmDelete(id)))):
                let database = database
                return .run { _ in
                    try await database.write { db in
                        try Thing.where { $0.id.eq(id) }.delete().execute(db)
                    }
                } catch: { error, send in
                    await send(.operationFailed(error.localizedDescription))
                }

            case .destination:
                return .none

            case let .editButtonTapped(thing):
                state.destination = .form(ThingFormFeature.State(thing: thing))
                return .none

            case let .moved(source, destination):
                // Replay the move on a copy to find the dropped thing's new
                // neighbors, then generate a key between them. Only the moved
                // thing's `rank` changes — a single-record write that plays well
                // with sync — so its neighbors keep their existing keys.
                // `source` was computed by SwiftUI against the rows it last
                // rendered; `things` can shrink underneath us between render and
                // this reduce if a sync write (or delete cascade) arrives mid-drag.
                // Bounds-check before indexing so a stale index can't trap.
                guard let sourceIndex = source.first, sourceIndex < state.things.count
                else { return .none }
                let moved = state.things[sourceIndex]
                var reordered = state.things
                reordered.move(fromOffsets: source, toOffset: destination)
                guard
                    reordered.map(\.id) != state.things.map(\.id),
                    let newIndex = reordered.firstIndex(where: { $0.id == moved.id })
                else { return .none }
                let before = newIndex > 0 ? reordered[newIndex - 1].rank : nil
                let after = newIndex < reordered.count - 1 ? reordered[newIndex + 1].rank : nil
                let newRank = FractionalIndex.keyBetween(before, after)
                let now = now
                let database = database
                return .run { _ in
                    try await database.write { db in
                        try Thing.where { $0.id.eq(moved.id) }
                            .update {
                                $0.rank = newRank
                                $0.updatedAt = now
                            }
                            .execute(db)
                    }
                } catch: { error, send in
                    await send(.operationFailed(error.localizedDescription))
                }

            case let .operationFailed(message):
                state.destination = .alert(.operationFailed(message))
                return .none

            case .shareButtonTapped:
                // `share(record:)` is idempotent: it returns the existing share
                // if the vault is already shared, so the same button both invites
                // the first participant and re-opens the management sheet later.
                // It throws if the vault hasn't synced to iCloud yet (or iCloud is
                // unavailable); we surface that through the existing alert.
                let syncEngine = syncEngine
                let vault = state.vault
                return .run { send in
                    let sharedRecord = try await syncEngine.share(record: vault) { share in
                        share[CKShare.SystemFieldKey.title] =
                            vault.name.isEmpty ? "Untitled Vault" : vault.name
                    }
                    await send(.shareResponse(sharedRecord))
                } catch: { error, send in
                    await send(.operationFailed(error.localizedDescription))
                }

            case .shareDismissed:
                state.sharedRecord = nil
                return .none

            case let .shareResponse(sharedRecord):
                state.sharedRecord = sharedRecord
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension VaultDetailFeature.Destination.State: Equatable {}

extension AlertState where Action == VaultDetailFeature.Destination.Alert {
    /// Delete confirmation. The alert's Delete button uses `role: .destructive`
    /// (standard red alert button); the *swipe* delete button is plain + red.
    static func confirmDelete(_ thing: Thing) -> Self {
        AlertState {
            TextState("Delete Thing?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmDelete(thing.id)) {
                TextState("Delete")
            }
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            let text = thing.text.isEmpty ? "Untitled" : thing.text
            return TextState("\u{201C}\(text)\u{201D} will be deleted.")
        }
    }
}

public struct VaultDetailView: View {
    @Bindable var store: StoreOf<VaultDetailFeature>

    public init(store: StoreOf<VaultDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        List {
            ForEach(store.things) { thing in
                Text(thing.text.isEmpty ? "Untitled" : thing.text)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Plain button tinted red — intentionally NOT
                        // `role: .destructive`. Full swipe is disabled so it
                        // can't bypass the confirmation alert.
                        Button("Delete") {
                            store.send(.deleteButtonTapped(thing))
                        }
                        .tint(.red)
                        Button("Edit") {
                            store.send(.editButtonTapped(thing))
                        }
                        .tint(.blue)
                    }
            }
            .onMove { source, destination in
                store.send(.moved(source, destination))
            }
        }
        .navigationTitle(store.vault.name.isEmpty ? "Untitled Vault" : store.vault.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Label("Add Thing", systemImage: "plus")
                }
            }
            // Sharing uses `CloudSharingView`, which is only available where UIKit
            // is (iPhone/iPad). The user opted out of a native-macOS path, so the
            // button is simply absent there.
            #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.shareButtonTapped)
                    } label: {
                        Label("Share Vault", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            #endif
        }
        .overlay {
            if store.things.isEmpty {
                ContentUnavailableView(
                    "No Things",
                    systemImage: "tray",
                    description: Text("Tap + to add your first thing.")
                )
            }
        }
        .sheet(
            item: $store.scope(state: \.destination?.form, action: \.destination.form)
        ) { formStore in
            ThingFormView(store: formStore)
        }
        .alert(
            $store.scope(state: \.destination?.alert, action: \.destination.alert)
        )
        // Present Apple's share sheet while a `SharedRecord` is set. Dismissing it
        // (swipe-down, Done, or Stop Sharing) clears the record via `.shareDismissed`.
        #if os(iOS)
            .sheet(
                item: Binding(
                    get: { store.sharedRecord },
                    set: { if $0 == nil { store.send(.shareDismissed) } }
                )
            ) { sharedRecord in
                CloudSharingView(sharedRecord: sharedRecord)
            }
        #endif
    }
}
