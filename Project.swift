import ProjectDescription

let bundleID = "studio.groeneveld.SyncThings"
let deploymentTargets: DeploymentTargets = .multiplatform(iOS: "17.0", macOS: "14.0")
let destinations: Destinations = [.iPhone, .iPad, .mac]

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.0",
    "CODE_SIGN_STYLE": "Automatic",
    // Read the signing team from the environment so it is never hard-coded.
    // Building to the simulator does not require it.
    "DEVELOPMENT_TEAM": "$(DEVELOPMENT_TEAM)",
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
