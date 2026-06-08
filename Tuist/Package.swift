// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    // Leave all external packages as static products (the Tuist default). They
    // are linked once into each final binary, which avoids the duplicate-class
    // crashes you get when shared transitive deps (GRDB, Sharing, …) are baked
    // into multiple dynamic frameworks.
    let packageSettings = PackageSettings()
#endif

let package = Package(
    name: "SyncThings",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    ]
)
