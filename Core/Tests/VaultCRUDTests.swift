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
