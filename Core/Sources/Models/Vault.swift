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

extension Vault.Draft: Equatable {}

// All of Draft's members (UUID?, String, Date) are Sendable value types, so the
// generated `Draft` is safe to send across concurrency domains — e.g. captured
// in a `.run` effect to be saved. The `@Table` macro does not add this for us.
extension Vault.Draft: Sendable {}
