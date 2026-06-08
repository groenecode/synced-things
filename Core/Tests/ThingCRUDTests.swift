import ComposableArchitecture
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import SyncThingsCore

@MainActor
@Suite struct ThingFormValidationTests {
    @Test func saveDisabledForBlankText() {
        let vaultID = UUID(0)
        #expect(
            ThingFormFeature.State(draft: Thing.Draft(vaultID: vaultID, text: "   "))
                .isSaveDisabled
        )
        #expect(
            !ThingFormFeature.State(draft: Thing.Draft(vaultID: vaultID, text: "Milk"))
                .isSaveDisabled
        )
    }
}

@MainActor
@Suite(.dependencies { try $0.bootstrapDatabase() })
struct VaultDetailNavigationTests {
    @Dependency(\.defaultDatabase) var database

    @Test func addButtonTapped_presentsFormWithKeyAfterLastThing() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        // Seed an existing thing at rank "a0" so the new draft appends after it.
        try await database.write { db in
            try Vault.insert { vault }.execute(db)
            try Thing.insert {
                Thing(id: UUID(1), vaultID: vault.id, text: "existing", rank: "a0")
            }
            .execute(db)
        }

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        }
        store.exhaustivity = .off

        await store.send(.addButtonTapped) {
            $0.destination = .form(
                ThingFormFeature.State(
                    draft: Thing.Draft(vaultID: vault.id, rank: FractionalIndex.keyBetween("a0", nil))
                )
            )
        }
    }

    @Test func editButtonTapped_presentsSeededForm() async {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let thing = Thing(id: UUID(1), vaultID: vault.id, text: "Milk", rank: "a0")
        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        }
        await store.send(.editButtonTapped(thing)) {
            $0.destination = .form(ThingFormFeature.State(thing: thing))
        }
    }

    @Test func deleteButtonTapped_presentsConfirmAlert() async {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let thing = Thing(id: UUID(1), vaultID: vault.id, text: "Milk", rank: "a0")
        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        }
        await store.send(.deleteButtonTapped(thing)) {
            $0.destination = .alert(.confirmDelete(thing))
        }
    }
}

@MainActor
@Suite(.dependencies { try $0.bootstrapDatabase() })
struct ThingCRUDIntegrationTests {
    // These tests assert via a direct DB read rather than `store.state.things`,
    // because the `@FetchAll` refresh is asynchronous and is NOT awaited by
    // `store.finish()` — only the write effect is.
    @Dependency(\.defaultDatabase) var database

    @Test func savingNewThing_insertsWithStampedDateAndRank() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        try await database.write { db in
            try Vault.insert { vault }.execute(db)
        }

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 1234)
        }
        store.exhaustivity = .off

        await store.send(.addButtonTapped)
        await store.send(.destination(.presented(.form(.binding(.set(\.draft.text, "Buy milk"))))))
        await store.send(.destination(.presented(.form(.saveButtonTapped))))
        await store.finish()

        let things = try await database.read { db in try Thing.fetchAll(db) }
        #expect(things.count == 1)
        #expect(things.first?.text == "Buy milk")
        #expect(things.first?.vaultID == vault.id)
        // First key in an empty vault.
        #expect(things.first?.rank == FractionalIndex.keyBetween(nil, nil))
        #expect(things.first?.updatedAt == Date(timeIntervalSince1970: 1234))
    }

    @Test func editingThing_updatesTextAndStampsDateAndPreservesRank() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let thingID = UUID(1)
        try await database.write { db in
            try Vault.insert { vault }.execute(db)
            try Thing.insert {
                Thing(
                    id: thingID,
                    vaultID: vault.id,
                    text: "Milk",
                    rank: "a5",
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
        }

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 9999)
        }
        store.exhaustivity = .off

        let thing = Thing(
            id: thingID, vaultID: vault.id, text: "Milk", rank: "a5",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        await store.send(.editButtonTapped(thing))
        await store.send(.destination(.presented(.form(.binding(.set(\.draft.text, "Oat milk"))))))
        await store.send(.destination(.presented(.form(.saveButtonTapped))))
        await store.finish()

        let saved = try await database.read { db in
            try Thing.where { $0.id.eq(thingID) }.fetchOne(db)
        }
        #expect(saved?.text == "Oat milk")
        #expect(saved?.rank == "a5")
        #expect(saved?.updatedAt == Date(timeIntervalSince1970: 9999))
    }

    @Test func confirmingDelete_removesThing() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let thingID = UUID(1)
        let thing = Thing(id: thingID, vaultID: vault.id, text: "Milk", rank: "a0")
        try await database.write { db in
            try Vault.insert { vault }.execute(db)
            try Thing.insert { thing }.execute(db)
        }

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        }
        store.exhaustivity = .off

        await store.send(.deleteButtonTapped(thing))
        await store.send(.destination(.presented(.alert(.confirmDelete(thingID)))))
        await store.finish()

        let count = try await database.read { db in try Thing.fetchCount(db) }
        #expect(count == 0)
    }

    @Test func cancelingDelete_keepsThing() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let thingID = UUID(1)
        let thing = Thing(id: thingID, vaultID: vault.id, text: "Milk", rank: "a0")
        try await database.write { db in
            try Vault.insert { vault }.execute(db)
            try Thing.insert { thing }.execute(db)
        }

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        }
        store.exhaustivity = .off

        await store.send(.deleteButtonTapped(thing))
        await store.send(.destination(.dismiss))
        await store.finish()

        let count = try await database.read { db in try Thing.fetchCount(db) }
        #expect(count == 1)
    }

    private nonisolated static let seededAt = Date(timeIntervalSince1970: 0)

    private func seedThreeThings(in vault: Vault) async throws -> (UUID, UUID, UUID) {
        let (t0, t1, t2) = (UUID(1), UUID(2), UUID(3))
        try await database.write { db in
            try Vault.insert { vault }.execute(db)
            for (id, text, rank) in [(t0, "0", "a0"), (t1, "1", "a1"), (t2, "2", "a2")] {
                try Thing.insert {
                    Thing(id: id, vaultID: vault.id, text: text, rank: rank, updatedAt: Self.seededAt)
                }
                .execute(db)
            }
        }
        return (t0, t1, t2)
    }

    private func orderedThings(in vault: Vault) async throws -> [Thing] {
        try await database.read { db in
            try Thing.where { $0.vaultID.eq(vault.id) }.order { ($0.rank, $0.id) }.fetchAll(db)
        }
    }

    @Test func movingThingToEnd_rewritesOnlyMovedThingsRank() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let (t0, t1, t2) = try await seedThreeThings(in: vault)

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 9999)
        }
        store.exhaustivity = .off

        await store.send(.moved(IndexSet(integer: 0), 3))
        await store.finish()

        let things = try await orderedThings(in: vault)
        #expect(things.map(\.id) == [t1, t2, t0])
        // Only the moved thing changed — its rank (to a key after the last
        // neighbor) and its `updatedAt`; its neighbors kept their keys and dates.
        #expect(things.first { $0.id == t0 }?.rank == FractionalIndex.keyBetween("a2", nil))
        #expect(things.first { $0.id == t0 }?.updatedAt == Date(timeIntervalSince1970: 9999))
        #expect(things.first { $0.id == t1 }?.rank == "a1")
        #expect(things.first { $0.id == t1 }?.updatedAt == Self.seededAt)
        #expect(things.first { $0.id == t2 }?.rank == "a2")
        #expect(things.first { $0.id == t2 }?.updatedAt == Self.seededAt)
    }

    @Test func movingThingToFront_generatesKeyBeforeAll() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let (t0, t1, t2) = try await seedThreeThings(in: vault)

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 9999)
        }
        store.exhaustivity = .off

        await store.send(.moved(IndexSet(integer: 2), 0))
        await store.finish()

        let things = try await orderedThings(in: vault)
        #expect(things.map(\.id) == [t2, t0, t1])
        #expect(things.first { $0.id == t2 }?.rank == FractionalIndex.keyBetween(nil, "a0"))
        #expect(things.first { $0.id == t2 }?.updatedAt == Date(timeIntervalSince1970: 9999))
    }

    @Test func noOpMove_doesNotChangeRanks() async throws {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let (t0, t1, t2) = try await seedThreeThings(in: vault)

        let store = TestStore(initialState: VaultDetailFeature.State(vault: vault)) {
            VaultDetailFeature()
        }
        store.exhaustivity = .off

        // Dropping index 0 back at offset 0 reorders nothing.
        await store.send(.moved(IndexSet(integer: 0), 0))
        await store.finish()

        let things = try await orderedThings(in: vault)
        #expect(things.map(\.id) == [t0, t1, t2])
        #expect(things.map(\.rank) == ["a0", "a1", "a2"])
        // No write happened, so timestamps are untouched.
        #expect(things.allSatisfy { $0.updatedAt == Self.seededAt })
    }
}
