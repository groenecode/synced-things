import ProjectDescription

let bundleID = "studio.groeneveld.SyncThings"
let deploymentTargets: DeploymentTargets = .multiplatform(iOS: "17.0", macOS: "14.0")
let destinations: Destinations = [.iPhone, .iPad, .mac]

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
    "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    // Read the signing team from the environment so it is never hard-coded.
    // Building to the simulator does not require it.
    "DEVELOPMENT_TEAM": "$(DEVELOPMENT_TEAM)",
    // Xcode's "recommended settings" — encoded here so they survive
    // `tuist generate` (the .xcodeproj is generated and gitignored).
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "ENABLE_MODULE_VERIFIER": "YES",
    "MODULE_VERIFIER_SUPPORTED_LANGUAGES": "objective-c objective-c++",
    "MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS": "gnu17 gnu++20",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
]

let project = Project(
    name: "SyncThings",
    organizationName: "Groeneveld Studio",
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: "SyncThings",
            destinations: destinations,
            product: .app,
            bundleId: bundleID,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Sync Things",
                "CKSharingSupported": true,
                "UIBackgroundModes": ["remote-notification"],
                "UILaunchScreen": [:],
            ]),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            entitlements: "App/SyncThings.entitlements",
            dependencies: [
                .target(name: "SyncThingsCore"),
                .external(name: "ComposableArchitecture"),
                .external(name: "SQLiteData"),
                .external(name: "Dependencies"),
            ]
        ),
        .target(
            name: "SyncThingsCore",
            destinations: destinations,
            product: .staticFramework,
            bundleId: "\(bundleID).Core",
            deploymentTargets: deploymentTargets,
            sources: ["Core/Sources/**"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .external(name: "SQLiteData"),
                .external(name: "Dependencies"),
            ]
        ),
        .target(
            name: "SyncThingsTests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "\(bundleID).Tests",
            deploymentTargets: deploymentTargets,
            sources: ["Core/Tests/**"],
            dependencies: [
                .target(name: "SyncThingsCore"),
                .external(name: "ComposableArchitecture"),
                .external(name: "DependenciesTestSupport"),
            ]
        ),
    ]
)
