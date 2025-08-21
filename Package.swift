// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PassageSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "PassageSDK",
            targets: ["PassageSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.1")
    ],
    targets: [
        .target(
            name: "PassageSDK",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ]),
        .testTarget(
            name: "PassageSDKTests",
            dependencies: ["PassageSDK"]),
    ]
)
