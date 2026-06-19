// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuizEditor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuizEditorCore", targets: ["QuizEditorCore"]),
        .executable(name: "QuizEditorApp", targets: ["QuizEditorApp"])
    ],
    targets: [
        .target(name: "QuizEditorCore"),
        .executableTarget(name: "QuizEditorApp", dependencies: ["QuizEditorCore"]),
        .testTarget(name: "QuizEditorCoreTests", dependencies: ["QuizEditorCore"])
    ]
)
