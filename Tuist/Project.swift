import ProjectDescription

let project = Project(
  name: "Chameleon",
  organizationName: "ProjectChameleon",
  targets: [
    Target(
      name: "Chameleon",
      platform: .iOS,
      product: .app,
      bundleId: "com.tsimpson.chameleon",
      deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone]),
      infoPlist: .default,
      sources: ["Sources/**"],
      resources: ["Resources/**"],
      dependencies: []
    ),
    Target(
      name: "ChameleonTests",
      platform: .iOS,
      product: .unitTests,
      bundleId: "com.tsimpson.chameleonTests",
      deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone]),
      infoPlist: .default,
      sources: ["Tests/Unit/**"],
      dependencies: [.target(name: "Chameleon")]
    ),
    Target(
      name: "ChameleonUITests",
      platform: .iOS,
      product: .uiTests,
      bundleId: "com.tsimpson.chameleonUITests",
      deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone]),
      infoPlist: .default,
      sources: ["Tests/UI/**"],
      dependencies: [.target(name: "Chameleon")]
    )
  ]
)
