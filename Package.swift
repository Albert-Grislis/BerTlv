// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BerTlv",
    products: [
        .library(
            name: "BerTlv",
            targets: ["BerTlv"]
        ),
    ],
    targets: [
        .target(
            name: "BerTlv",
            exclude: ["include/BerTlv-Prefix.pch"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("."),]
        ),
    ]
)
