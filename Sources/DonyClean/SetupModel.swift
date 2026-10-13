import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement
import DonyCore

extension AppModel {
    func setCharacterMode(_ mode: CharacterMode) {
        characterMode = mode; menuAnimator.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "characterMode")
    }
    func saveConnectedTools() { UserDefaults.standard.set(connectedTools.map(\.rawValue).sorted(), forKey: "connectedTools") }
    func refreshToolConnections() {
        let running = Set(aiUsage.map(\.tool))
        for tool in AITool.allCases {
            toolStatuses[tool] = running.contains(tool) ? "사용 중" : DevelopmentRuntime.installed(tool) ? "설치됨" : "직접 연결"
        }
        if UserDefaults.standard.stringArray(forKey: "connectedTools") == nil {
            connectedTools = Set(AITool.allCases.filter { running.contains($0) || DevelopmentRuntime.installed($0) })
            if connectedTools.isEmpty { connectedTools = [.terminal, .other] }
        }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: notificationStatus = "허용됨"
            case .denied: notificationStatus = "꺼짐"
            default: notificationStatus = "미설정"
            }
        }
    }
    func completeOnboarding() {
        saveConnectedTools(); UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        onboardingShown = false; section = .development
    }
    func openPrivacySettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
    func openFilePermissions() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!) }
}
