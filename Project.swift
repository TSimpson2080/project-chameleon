import ProjectDescription

let projectSettings = Settings.settings(
    base: [
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    ],
    configurations: [
        .debug(name: "Debug"),
        .release(
            name: "Release",
            settings: [
                "SWIFT_OPTIMIZATION_LEVEL": "-O",
                "COPY_PHASE_STRIP": "YES",
            ]
        ),
    ],
    defaultSettings: .recommended
)

let project = Project(
    name: "Chameleon",
    settings: projectSettings,
    targets: [
        .target(
            name: "Chameleon",
            destinations: .iOS,
            product: .app,
            bundleId: "com.tsimpson.chameleon",
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "ReScope",
                    "CFBundleName": "ReScope",
                    "CFBundleShortVersionString": "1.0.0",
                    "CFBundleVersion": "14",
                    "CFBundleIconName": "AppIcon",
                    "EnableHangDiagnostics": true,
                    "NSPhotoLibraryUsageDescription": "Select photos to attach to change orders.",
                    "NSPhotoLibraryAddUsageDescription": "Save exported PDFs and diagnostics to your photo library if you choose.",
                    "UILaunchScreen": [
                        "UIColorName": "",
	                        "UIImageName": "",
	                    ],
	                ]
	            ),
            buildableFolders: [
                "Chameleon/Sources",
                "Chameleon/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "ChameleonTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.tsimpson.chameleonTests",
            infoPlist: .default,
            buildableFolders: [
                "Chameleon/Tests"
            ],
            dependencies: [.target(name: "Chameleon")]
        ),
    ]
)
