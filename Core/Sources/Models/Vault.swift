import Foundation
import SQLiteData

/// A named container of text ``Thing``s that can be synced via iCloud and shared
/// with other iCloud users.
///
/// A `Vault` is a *root record* — it has no foreign keys — which makes it
/// eligible to be shared through CloudKit. Its associated ``Thing``s are shared
/// along with it automatically.
@Table
public struct Vault: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String = ""
    /// Set from the `\.date.now` dependency at write time; the default is a
    /// referentially-transparent sentinel rather than a live `Date()`.
    public var createdAt: Date = .distantPast
}
