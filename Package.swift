// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FastDebatePaste",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FastDebatePaste",
            path: "Sources/FastDebatePaste",
            swiftSettings: [
                // The app leans on Carbon hotkey callbacks, CGEvent C APIs,
                // and shared singletons that don't fit Swift 6 strict
                // concurrency cleanly. Language mode 5 keeps that idiom
                // working without a forest of @MainActor/Sendable churn.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
