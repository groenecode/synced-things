import ComposableArchitecture
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import SyncThingsCore

@MainActor
@Suite struct VaultFormValidationTests {
    @Test func saveDisabledForBlankName() {
        #expect(VaultFormFeature.State(draft: Vault.Draft(name: "   ")).isSaveDisabled)
        #expect(!VaultFormFeature.State(draft: Vault.Draft(name: "Work")).isSaveDisabled)
    }
}

@MainActor
@Suite(.dependencies { try $0.bootstrapDatabase() })
struct VaultNavigationTests {
    @Test func addButtonTapped_presentsEmptyForm() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        await store.send(.addButtonTapped) {
            $0.destination = .form(VaultFormFeature.State())
        }
    }

    @Test func editButtonTapped_presentsSeededForm() async {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        await store.send(.editButtonTapped(vault)) {
            $0.destination = .form(VaultFormFeature.State(vault: vault))
        }
    }

    @Test func deleteButtonTapped_presentsConfirmAlert() async {
        let vault = Vault(id: UUID(0), name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        await store.send(.deleteButtonTapped(vault)) {
            $0.destination = .alert(.confirmDelete(vault))
        }
    }
}

@MainActor
@Suite(.dependencies { try $0.bootstrapDatabase() })
struct VaultCRUDIntegrationTests {
    @Dependency(\.defaultDatabase) var database

    @Test func savingNewVault_insertsWithStampedDate() async throws {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 1234)
        }
        store.exhaustivity = .off

        await store.send(.addButtonTapped)
        await store.send(.destination(.presented(.form(.binding(.set(\.draft.name, "Personal"))))))
        await store.send(.destination(.presented(.form(.saveButtonTapped))))
        await store.finish()

        let vaults = try await database.read { db in try Vault.fetchAll(db) }
        #expect(vaults.count == 1)
        #expect(vaults.first?.name == "Personal")
        #expect(vaults.first?.createdAt == Date(timeIntervalSince1970: 1234))
    }

    @Test func editingVault_updatesNameAndPreservesCreatedAt() async throws {
        let vaultID = UUID(0)
        let created = Date(timeIntervalSince1970: 0)
        try await database.write { db in
            try Vault.insert { Vault(id: vaultID, name: "Work", createdAt: created) }
                .execute(db)
        }

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 9999)
        }
        store.exhaustivity = .off

        await store.send(.editButtonTapped(Vault(id: vaultID, name: "Work", createdAt: created)))
        await store.send(.destination(.presented(.form(.binding(.set(\.draft.name, "Work Stuff"))))))
        await store.send(.destination(.presented(.form(.saveButtonTapped))))
        await store.finish()

        let vault = try await database.read { db in
            try Vault.where { $0.id.eq(vaultID) }.fetchOne(db)
        }
        #expect(vault?.name == "Work Stuff")
        #expect(vault?.createdAt == created)
    }

    @Test func confirmingDelete_removesVault() async throws {
        let vaultID = UUID(0)
        let vault = Vault(id: vaultID, name: "Work", createdAt: Date(timeIntervalSince1970: 0))
        try await database.write { db in
            try Vault.insert { vault }.execute(db)
        }

        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        store.exhaustivity = .off

        await store.send(.deleteButtonTapped(vault))
        await store.send(.destination(.presented(.alert(.confirmDelete(vaultID)))))
        await store.finish()

        let count = try await database.read { db in try Vault.fetchCount(db) }
        #expect(count == 0)
    }
}
