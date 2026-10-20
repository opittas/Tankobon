// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BookKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BookKit",
            targets: ["BookKit"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Ponte para a libarchive do sistema, usada para abrir RAR, CBR e 7z.
        .target(
            name: "CArchive",
            linkerSettings: [
                .linkedLibrary("archive"),
            ]
        ),
        // UnRAR oficial (RARLAB), para abrir qualquer RAR/CBR, inclusive RAR4 "sólido".
        // Licença em Sources/CUnrar/license.txt.
        .target(
            name: "CUnrar",
            sources: [
                "rar.cpp", "strlist.cpp", "strfn.cpp", "pathfn.cpp", "smallfn.cpp", "global.cpp",
                "file.cpp", "filefn.cpp", "filcreat.cpp", "archive.cpp", "arcread.cpp", "unicode.cpp",
                "system.cpp", "crypt.cpp", "crc.cpp", "rawread.cpp", "encname.cpp", "resource.cpp",
                "match.cpp", "timefn.cpp", "rdwrfn.cpp", "consio.cpp", "options.cpp", "errhnd.cpp",
                "rarvm.cpp", "secpassword.cpp", "rijndael.cpp", "getbits.cpp", "sha1.cpp", "sha256.cpp",
                "blake2s.cpp", "hash.cpp", "extinfo.cpp", "extract.cpp", "volume.cpp", "list.cpp",
                "find.cpp", "unpack.cpp", "headers.cpp", "threadpool.cpp", "rs16.cpp", "cmddata.cpp",
                "ui.cpp", "largepage.cpp", "filestr.cpp", "scantree.cpp", "dll.cpp", "qopen.cpp",
                "TankobonRar.cpp",
            ],
            cxxSettings: [
                .define("RARDLL"),
                .define("RAR_SMP"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE"),
            ]
        ),
        .target(
            name: "BookKit",
            dependencies: ["CArchive", "CUnrar"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "BookKitTests",
            dependencies: ["BookKit", "CUnrar"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ],
    cxxLanguageStandard: .cxx17
)
