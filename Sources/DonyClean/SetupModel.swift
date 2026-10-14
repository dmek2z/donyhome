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
        for tool in AITool.allCases where connectionCheckedAt == nil {
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
    /// 처음 연동할 때 도구에서 찾은 프로젝트를 모두 정리 대상으로 켠다(이후 사용자가 끈 항목은 존중). 한 번만 적용한다.
    func enableDiscoveredProjectsOnce() {
        guard !UserDefaults.standard.bool(forKey: "projectsDefaultSynced"), !linkedProjects.isEmpty else { return }
        for index in linkedProjects.indices where linkedProjects[index].discovered { linkedProjects[index].enabled = true }
        UserDefaults.standard.set(true, forKey: "projectsDefaultSynced")
        saveProjectSettings()
    }
    func completeOnboarding() {
        saveConnectedTools(); UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        onboardingShown = false; section = .development
        if restartNeeded { restartForPermissions() }
    }
    func openPrivacySettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
    func openFilePermissions() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!) }
}
