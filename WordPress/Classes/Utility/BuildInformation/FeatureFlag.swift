/// FeatureFlag exposes a series of features to be conditionally enabled on
/// different builds.
@objc
enum FeatureFlag: Int {
    case exampleFeature
    case jetpackDisconnect
    case activity
    case usernameChanging
    case zendeskMobile
    case saveForLater

    /// Returns a boolean indicating if the feature is enabled
    var enabled: Bool {
        switch self {
        case .exampleFeature:
            return true
        case .jetpackDisconnect:
            return BuildConfiguration.current == .localDeveloper
        case .activity:
            return BuildConfiguration.current ~= [.localDeveloper, .a8cBranchTest, .a8cPrereleaseTesting]
        case .usernameChanging:
            return BuildConfiguration.current == .localDeveloper
        case .zendeskMobile:
            return BuildConfiguration.current == .localDeveloper
        case .saveForLater:
            return false
        }
    }
}

/// Objective-C bridge for FeatureFlag.
///
/// Since we can't expose properties on Swift enums we use a class instead
class Feature: NSObject {
    /// Returns a boolean indicating if the feature is enabled
    @objc static func enabled(_ feature: FeatureFlag) -> Bool {
        return feature.enabled
    }
}
