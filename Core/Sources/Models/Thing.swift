import Foundation
import SQLiteData

/// A small piece of text living inside a ``Vault``.
///
/// A `Thing` has a single foreign key (`vaultID`), so when its parent ``Vault``
/// is shared it is shared along with it.
@Table
public struct Thing: Identifiable, Equatable {
    public let id: UUID
    public var vaultID: Vault.ID
    public var text: String = ""
    /// Manual ordering within a vault (lower sorts first).
    public var position: Int = 0
    /// Avoids the iCloud-reserved column name `modificationDate`.
    public var updatedAt: Date = Date()
}
