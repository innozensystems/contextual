// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Contextual",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Contextual", targets: ["Contextual"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.5.0"),
    ],
    targets: [
        .target(
            name: "Contextual",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Sources"
        ),
    ]
)
