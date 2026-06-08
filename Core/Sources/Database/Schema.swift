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
            // Attaches the iCloud sync metadatabase so `SyncMetadata` (share
            // status, etc.) is queryable. It needs a CloudKit container, which
            // is unavailable on unsigned simulator builds — make it best-effort
            // so the local database still opens.
            do {
                try db.attachMetadatabase()
            } catch {
                logger.error("metadatabase unavailable, sync metadata disabled: \(error)")
            }
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
        //
        // Sync is best-effort: the local database is the source of truth and the
        // app is fully usable without it. Starting the engine can fail for
        // reasons outside our control — an unsigned simulator build has no
        // CloudKit entitlement, the device may not be signed into iCloud, etc.
        // Those must not take down the app, so we log and continue local-only.
        if context == .live {
            do {
                defaultSyncEngine = try SyncEngine(
                    for: database,
                    tables: Vault.self, Thing.self
                )
            } catch {
                logger.error("iCloud sync unavailable, continuing local-only: \(error)")
            }
        }
    }
}
