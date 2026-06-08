import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import SyncThingsCore

@Suite(.dependencies { try $0.bootstrapDatabase() })
struct SchemaTests {
    @Dependency(\.defaultDatabase) var database

    @Test func insertAndFetchVault() async throws {
        try await database.write { db in
            try Vault.insert { Vault.Draft(name: "Personal") }.execute(db)
        }

        let vaults = try await database.read { db in try Vault.fetchAll(db) }

        #expect(vaults.count == 1)
        #expect(vaults.first?.name == "Personal")
    }

    @Test func deletingVaultCascadesToThings() async throws {
        let vaultID = UUID(0)
        try await database.write { db in
            try Vault.insert {
                Vault(id: vaultID, name: "Work", createdAt: Date(timeIntervalSince1970: 0))
            }
            .execute(db)
            try Thing.insert { Thing.Draft(vaultID: vaultID, text: "hello") }.execute(db)
        }

        try await database.write { db in
            try Vault.where { $0.id.eq(vaultID) }.delete().execute(db)
        }

        let things = try await database.read { db in try Thing.fetchAll(db) }
        #expect(things.isEmpty)
    }
}
