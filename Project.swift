import ProjectDescription

let project = Project(
    name: "Chameleon",
    targets: [
        .target(
            name: "Chameleon",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.Chameleon",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                    "NSPhotoLibraryUsageDescription": "Select photos to attach to change orders.",
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
            bundleId: "dev.tuist.ChameleonTests",
            infoPlist: .default,
            buildableFolders: [
                "Chameleon/Tests"
            ],
            dependencies: [.target(name: "Chameleon")]
        ),
    ]
)
