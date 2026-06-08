import Foundation
import SQLiteData

/// A named container of text ``Thing``s that can be synced via iCloud and shared
/// with other iCloud users.
///
/// A `Vault` is a *root record* — it has no foreign keys — which makes it
/// eligible to be shared through CloudKit. Its associated ``Thing``s are shared
/// along with it automatically.
@Table
public struct Vault: Identifiable, Equatable {
    public let id: UUID
    public var name: String = ""
    public var createdAt: Date = Date()
}
