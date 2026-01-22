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
  organizationName: "ProjectChameleon",
  settings: projectSettings,
  targets: [
    Target(
      name: "Chameleon",
      platform: .iOS,
      product: .app,
      bundleId: "com.tsimpson.chameleon",
      deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone]),
	      infoPlist: .extendingDefault(with: [
	        "CFBundleShortVersionString": "1.0.0",
	        "CFBundleVersion": "6",
	        "CFBundleIconName": "AppIcon",
	        "EnableHangDiagnostics": true,
	        "NSPhotoLibraryUsageDescription": "Select photos to attach to change orders.",
	        "NSPhotoLibraryAddUsageDescription": "Save exported PDFs and diagnostics to your photo library if you choose.",
	      ]),
      sources: ["Chameleon/Sources/**"],
      resources: ["Chameleon/Resources/**"],
      dependencies: []
    ),
    Target(
      name: "ChameleonTests",
      platform: .iOS,
      product: .unitTests,
      bundleId: "com.tsimpson.chameleonTests",
      deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone]),
      infoPlist: .default,
      sources: ["Chameleon/Tests/**"],
      dependencies: [.target(name: "Chameleon")]
    ),
    Target(
      name: "ChameleonUITests",
      platform: .iOS,
      product: .uiTests,
      bundleId: "com.tsimpson.chameleonUITests",
      deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone]),
      infoPlist: .default,
      sources: ["Chameleon/Tests/**"],
      dependencies: [.target(name: "Chameleon")]
    )
  ]
)
