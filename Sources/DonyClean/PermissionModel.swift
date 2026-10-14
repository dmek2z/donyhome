import AppKit
import SwiftUI
import UserNotifications
import DonyCore

extension AppModel {
    func showPermissions(continueScan: Bool) {
        scanAfterPermissions = continueScan
        if continueScan { ScanContinuation.save(folder: folder) }
        permissionError = nil; permissionsShown = true
        refreshAccess()
        refreshToolConnections()
    }

    @discardableResult
    func refreshAccess() -> Task<Void, Never> {
        if let task = permissionAccessTask { return task }; checkingAccess = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = folder
        let task = Task {
            let result = await Task.detached(priority: .utility) {
                let disk = PermissionAccess.protectedFile(home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"))
                var folders: [String: PermissionAccess] = [:]
                for path in Set([folder] + ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }) {
                    folders[path.path] = PermissionAccess.directory(path)
                }
                return (disk, folders)
            }.value
            diskAccess = result.0; folderAccess = result.1; checkingAccess = false; permissionAccessTask = nil
        }
        permissionAccessTask = task
        return task
    }

    func preparePermissionSettings(filesOnly: Bool = false) {
        if scanAfterPermissions { ScanContinuation.save(folder: folder) }
        restartNeeded = true
        if filesOnly { openFilePermissions() } else { openPrivacySettings() }
    }

    func requestSelectedPermissions(notifications: Bool, paste: Bool, clipboard: ClipboardController) {
        guard !requestingPermissions else { return }
        requestingPermissions = true
        permissionError = nil
        Task {
            defer { requestingPermissions = false }
            // Request optional prompts before Settings, where macOS may quit the app.
            if notifications {
                do {
                    let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                    notifyEnabled = granted; UserDefaults.standard.set(granted, forKey: "overloadNotifications")
                } catch { permissionError = error.localizedDescription }
            }
            if paste && !clipboard.accessibilityAllowed { clipboard.requestAccessibility() }
            // Opening each configured directory lets macOS request all file scopes
            // in this pass, before the single final restart.
            await refreshAccess().value
            refreshToolConnections()
            if diskAccess != .allowed { preparePermissionSettings() }
        }
    }

    func cancelPermissions() {
        if scanAfterPermissions { ScanContinuation.clear() }
        scanAfterPermissions = false; permissionsShown = false
    }

    func finishPermissions() {
        permissionSetupReviewed = true
        UserDefaults.standard.set(true, forKey: "permissionSetupReviewed")
        if restartNeeded { restartForPermissions(); return }
        let runScan = scanAfterPermissions
        ScanContinuation.clear(); scanAfterPermissions = false; permissionsShown = false
        if runScan { performSmartScan() }
    }

    func restartForPermissions() {
        guard !busy else { return }
        if scanAfterPermissions { ScanContinuation.save(folder: folder) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "for attempt in $(/usr/bin/seq 1 150); do if ! /bin/kill -0 \"$1\" 2>/dev/null; then exec /usr/bin/open -n \"$2\"; fi; /bin/sleep 0.2; done; exit 1", "donyhome-relaunch", String(getpid()), Bundle.main.bundleURL.path]
        do {
            try process.run()
            permissionsShown = false; preferencesShown = false; onboardingShown = false
            // AppKit can refuse termination while a sheet is attached. End them
            // first, then let SwiftUI process dismissal before terminating.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } catch { permissionError = "다시 열지 못했어요: " + error.localizedDescription }
    }

    func resumePendingScan() {
        guard !resumedScanChecked, !busy else { return }; resumedScanChecked = true
        guard !FirstLaunchSetup.shouldShow() else { return }
        guard let scope = ScanContinuation.take() else { return }
        folder = scope; UserDefaults.standard.set(scope.path, forKey: "scanFolder")
        permissionSetupReviewed = true; UserDefaults.standard.set(true, forKey: "permissionSetupReviewed")
        onboardingShown = false; preferencesShown = false; permissionsShown = false
        performSmartScan()
    }
}
