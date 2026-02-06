// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "FFmpeg-iOS-Lame",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "FFmpeg-iOS-Lame",
            targets: [
                "avcodec", "avutil", "avformat", "avfilter", "avdevice", "swscale", "swresample",
                "fftools", "Dummy",
            ]),
    ],
    dependencies: [
        .package(path: "../FFmpeg-iOS-Support"),
    ],
    targets: [
        .binaryTarget(name: "avcodec", path: "Frameworks/avcodec.xcframework"),
        .binaryTarget(name: "avutil", path: "Frameworks/avutil.xcframework"),
        .binaryTarget(name: "avformat", path: "Frameworks/avformat.xcframework"),
        .binaryTarget(name: "avfilter", path: "Frameworks/avfilter.xcframework"),
        .binaryTarget(name: "avdevice", path: "Frameworks/avdevice.xcframework"),
        .binaryTarget(name: "swscale", path: "Frameworks/swscale.xcframework"),
        .binaryTarget(name: "swresample", path: "Frameworks/swresample.xcframework"),
        .binaryTarget(name: "fftools", path: "Frameworks/fftools.xcframework"),
        .binaryTarget(name: "mp3lame", path: "Frameworks/mp3lame.xcframework"),
        .target(name: "Dummy", dependencies: [
            "fftools",
            "avcodec", "avformat", "avfilter", "avdevice", "avutil", "swscale", "swresample",
            "mp3lame",
            "FFmpeg-iOS-Support",
        ]),
        .testTarget(name: "FFmpeg-iOSTests",
                    dependencies: ["Dummy",]),
    ]
)
