import Foundation
import Darwin

/// Actual access, rather than an inference from an empty scan error list.
public enum PermissionAccess: String, Sendable {
    case allowed, denied, unavailable
    public var title: String {
        switch self { case .allowed: return "접근 가능"; case .denied: return "권한 필요"; case .unavailable: return "확인 필요" }
    }
    public static func classify(error: Int32) -> Self {
        error == EACCES || error == EPERM ? .denied : .unavailable
    }
    public static func directory(_ url: URL) -> Self {
        guard let directory = opendir(url.path) else { return classify(error: errno) }
        closedir(directory)
        return .allowed
    }
    public static func protectedFile(_ url: URL) -> Self {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return classify(error: errno) }
        close(descriptor)
        return .allowed
    }
}

public enum FirstLaunchSetup {
    public static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: "onboardingCompleted")
    }
    /// Claim before showing OS dialogs so a permission-driven restart cannot loop.
    public static func claimPermissionRequests(defaults: UserDefaults = .standard) -> Bool {
        guard shouldShow(defaults: defaults), !defaults.bool(forKey: "initialPermissionRequestsStarted") else { return false }
        defaults.set(true, forKey: "initialPermissionRequestsStarted")
        return true
    }
}
