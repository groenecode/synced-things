import Dependencies
import Foundation
import OSLog
import SQLiteData

private let logger = Logger(subsystem: "studio.groeneveld.SyncThings", category: "Database")

extension DependencyValues {
    /// Sets up the on-device SQLite database, runs migrations, and starts the
    /// iCloud `SyncEngine` for the ``Vault`` and ``Thing`` tables.
    ///
    /// Call this exactly once from the app entry point inside `prepareDependencies`.
    public mutating func bootstrapDatabase() throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Required so that `SyncMetadata` (share status, etc.) is queryable.
            try db.attachMetadatabase()
            #if DEBUG
                db.trace(options: .profile) {
                    guard
                        !SyncEngine.isSynchronizing,
                        !$0.expandedDescription.hasPrefix("--")
                    else { return }
                    logger.debug("\($0.expandedDescription)")
                }
            #endif
        }

        let database = try SQLiteData.defaultDatabase(configuration: configuration)

        var migrator = DatabaseMigrator()
        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("Create 'vaults' and 'things' tables") { db in
            try #sql("""
                CREATE TABLE "vaults" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "name" TEXT NOT NULL DEFAULT '',
                  "createdAt" TEXT NOT NULL DEFAULT (datetime('now'))
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "things" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "vaultID" TEXT NOT NULL REFERENCES "vaults"("id") ON DELETE CASCADE,
                  "text" TEXT NOT NULL DEFAULT '',
                  "position" INTEGER NOT NULL DEFAULT 0,
                  "updatedAt" TEXT NOT NULL DEFAULT (datetime('now'))
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE INDEX "index_things_on_vaultID" ON "things"("vaultID")
                """)
                .execute(db)
        }
        try migrator.migrate(database)

        defaultDatabase = database

        // Only run the iCloud sync engine in the live app. In tests and Xcode
        // previews we want a local, deterministic database with no background
        // CloudKit activity.
        if context == .live {
            defaultSyncEngine = try SyncEngine(
                for: database,
                tables: Vault.self, Thing.self
            )
        }
    }
}
