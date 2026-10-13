// Clipboard capture filtering and formatting adapted from Maccy Clipboard.swift
// Copyright (c) 2025 Alex Rodionov. MIT; see Resources/Clipboard/Maccy-LICENSE.txt.
import AppKit
import Foundation
import Fuse

public struct ClipboardRepresentation: Codable, Equatable, Sendable {
    public var type: String
    public var data: Data
    public init(type: String, data: Data) { self.type = type; self.data = data }
}
public struct ClipboardItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var representations: [[ClipboardRepresentation]]
    public var application: String?
    public var firstCopiedAt = Date()
    public var lastCopiedAt = Date()
    public var numberOfCopies = 1
    public var pinned = false
    public var recognizedText: String? = nil
    public var pinOrder: Int? = nil
    public var pinLetter: String? = nil
    public var customTitle: String? = nil
    public var text: String? {
        for group in representations {
            if let value = group.first(where: { $0.type == NSPasteboard.PasteboardType.string.rawValue }), let string = String(data: value.data, encoding: .utf8) { return string }
            if let value = group.first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }), let string = NSAttributedString(rtf: value.data, documentAttributes: nil)?.string { return string }
        }
        for group in representations {
            if let value = group.first(where: { $0.type == NSPasteboard.PasteboardType.html.rawValue }), let string = NSAttributedString(html: value.data, documentAttributes: nil)?.string { return string }
        }
        return nil
    }
    public var fileURLs: [URL] { representations.flatMap { $0 }.filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }.compactMap { String(data: $0.data, encoding: .utf8).flatMap(URL.init(string:)) } }
    public var imageData: Data? { representations.flatMap { $0 }.first { ["public.png", "public.tiff", "public.jpeg", "public.heic"].contains($0.type) }?.data }
    public var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if !fileURLs.isEmpty { return fileURLs.map(\.lastPathComponent).joined(separator: ", ") }
        if let text, !text.isEmpty { return String(text.prefix(1000)) }
        if imageData != nil { return recognizedText.flatMap { $0.isEmpty ? nil : String($0.prefix(1000)) } ?? "이미지" }
        return "서식 있는 콘텐츠"
    }
    public var byteCount: Int { representations.flatMap { $0 }.reduce(0) { $0 + $1.data.count } }
    public init(representations: [[ClipboardRepresentation]], application: String? = nil) { self.representations = representations; self.application = application }
}
public enum ClipboardSort: String, Codable, CaseIterable, Sendable { case lastCopiedAt, firstCopiedAt, numberOfCopies }
public enum ClipboardSearch: String, Codable, CaseIterable, Sendable { case exact, regexp, fuzzy, mixed }
public struct ClipboardPreferences: Codable, Equatable, Sendable {
    public var pinShortcut: ClipboardKeyShortcut? = nil
    public var deleteShortcut: ClipboardKeyShortcut? = nil
    public var appearance: ClipboardAppearance? = nil
    public var behavior: ClipboardBehavior? = nil
    public var limit = 200
    public var sort: ClipboardSort = .lastCopiedAt
    public var search: ClipboardSearch = .exact
    public var paused = false
    public var ignoredApps: [String] = []
    public var onlyListedApps = false
    public var ignoredTypes: [String] = []
    public var ignoredPatterns: [String] = []
    public var enabledTypes = ["public.utf8-plain-text", "public.rtf", "public.html", "public.png", "public.tiff", "public.jpeg", "public.heic", "public.file-url"]
    public var pinsAtBottom = false
    public var hotkeyEnabled = true
    public var hotkeyKeyCode: UInt32 = 8 // C
    public var hotkeyModifiers: UInt32 = 0x100 | 0x200 // command + shift
    public init() {}
}
public struct ClipboardKeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
}
public struct ClipboardAppearance: Codable, Equatable, Sendable {
    public var popupPosition = "커서"
    public var imageHeight = 40
    public var previewDelay = 1500
    public var showAppIcons = false
    public var showFooter = true
    public var showTitle = true
    public var showSpecialCharacters = false
    public init() {}
}
public struct ClipboardBehavior: Codable, Equatable, Sendable {
    public var pasteAutomatically = false
    public var plainText = false
    public var clearOnQuit = false
    public var clearSystemOnQuit = false
    public init() {}
}
public enum ClipboardSelection: Equatable, Sendable {
    case copy, paste(plainText: Bool)
    public static func action(behavior: ClipboardBehavior?, command: Bool, option: Bool, shift: Bool) -> Self {
        option || (behavior?.pasteAutomatically == true && !command) ? .paste(plainText: shift || behavior?.plainText == true) : .copy
    }
}
@MainActor public enum ClipboardCapture {
    public static let ignored = ["org.nspasteboard.AutoGeneratedType", "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword", "org.keepassxc.keepassxc"]
    public static let selfMarker = "com.donyhome.clipboard"
    public static func read(_ pasteboard: NSPasteboard, application: String?, preferences: ClipboardPreferences) -> ClipboardItem? {
        guard !preferences.paused else { return nil }
        if let application {
            let listed = preferences.ignoredApps.contains(application)
            if preferences.onlyListedApps ? !listed : listed { return nil }
            if ["com.1password.1password", "com.agilebits.onepassword7", "org.keepassxc.keepassxc", "com.bitwarden.desktop"].contains(application) { return nil }
        }
        let allTypes = Set((pasteboard.types ?? []).map(\.rawValue))
        guard allTypes.isDisjoint(with: Set(ignored + preferences.ignoredTypes + [selfMarker])), !allTypes.isDisjoint(with: Set(preferences.enabledTypes)) else { return nil }
        var groups: [[ClipboardRepresentation]] = []
        var total = 0
        for item in pasteboard.pasteboardItems ?? [] {
            if let string = item.string(forType: .string) {
                if preferences.ignoredPatterns.contains(where: { string.range(of: $0, options: .regularExpression) != nil }) { continue }
                if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.data(forType: .rtf) == nil && item.data(forType: .html) == nil { continue }
            }
            let wordLink = item.types.contains(NSPasteboard.PasteboardType("com.microsoft.Link-Source")) && item.types.contains(NSPasteboard.PasteboardType("com.microsoft.ObjectLink"))
            let contents = item.types.compactMap { type -> ClipboardRepresentation? in
                let raw = type.rawValue
                guard !raw.hasPrefix("dyn."), !raw.hasPrefix("com.microsoft.ole.source."), !["Apple Web Archive pasteboard type", "com.apple.webarchive", "org.nspasteboard.source"].contains(raw), !preferences.ignoredTypes.contains(raw) else { return nil }
                let supported = ["public.utf8-plain-text", "public.rtf", "public.html", "public.png", "public.tiff", "public.jpeg", "public.heic", "public.file-url"]
                if supported.contains(raw) && !preferences.enabledTypes.contains(raw) { return nil }
                if wordLink && ["com.microsoft.Link-Source", "com.microsoft.ObjectLink", "com.adobe.pdf"].contains(raw) { return nil }
                guard let data = item.data(forType: type), data.count <= 25_000_000 else { return nil }
                total += data.count
                return ClipboardRepresentation(type: raw, data: data)
            }
            if let derivedText = ClipboardItem(representations: [contents]).text, preferences.ignoredPatterns.contains(where: { derivedText.range(of: $0, options: .regularExpression) != nil }) { continue }
            if !contents.isEmpty { groups.append(contents.sorted { $0.type < $1.type }) }
        }
        guard !groups.isEmpty, total <= 50_000_000 else { return nil }
        return ClipboardItem(representations: groups, application: application)
    }
    public static func write(_ item: ClipboardItem, to pasteboard: NSPasteboard, plainText: Bool = false) -> Bool {
        let objects = item.representations.map { representations -> NSPasteboardItem in
            let object = NSPasteboardItem()
            var contents = representations
            if plainText {
                let group = ClipboardItem(representations: [representations])
                if let text = group.text {
                    let richTypes = [NSPasteboard.PasteboardType.string.rawValue, NSPasteboard.PasteboardType.rtf.rawValue, NSPasteboard.PasteboardType.html.rawValue, "public.rtfd", "com.apple.flat-rtfd"]
                    contents.removeAll { richTypes.contains($0.type) }
                    contents.append(ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8)))
                }
            }
            for value in contents { object.setData(value.data, forType: NSPasteboard.PasteboardType(value.type)) }
            object.setString("", forType: NSPasteboard.PasteboardType(selfMarker))
            return object
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }
}
public struct ClipboardStore: Sendable {
    public var url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: url))
    }
    public func save(_ items: [ClipboardItem]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(items).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
public enum ClipboardHistory {
    public static func adding(_ new: ClipboardItem, to items: [ClipboardItem], limit: Int) -> [ClipboardItem] {
        var result = items
        if let index = result.firstIndex(where: { $0.representations == new.representations }) {
            result[index].lastCopiedAt = new.lastCopiedAt; result[index].numberOfCopies += 1; result[index].application = new.application
        } else { result.append(new) }
        let unpinned = result.filter { !$0.pinned }.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
        let retained = Set(unpinned.prefix(max(1, min(10000, limit))).map(\.id))
        return result.filter { $0.pinned || retained.contains($0.id) }
    }
    public static func sorted(_ items: [ClipboardItem], by sort: ClipboardSort, pinsAtBottom: Bool = false) -> [ClipboardItem] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return pinsAtBottom ? !a.pinned : a.pinned }
            if a.pinned, b.pinned, a.pinOrder != b.pinOrder { return (a.pinOrder ?? 0) < (b.pinOrder ?? 0) }
            switch sort { case .lastCopiedAt: return a.lastCopiedAt > b.lastCopiedAt; case .firstCopiedAt: return a.firstCopiedAt > b.firstCopiedAt; case .numberOfCopies: return a.numberOfCopies == b.numberOfCopies ? a.lastCopiedAt > b.lastCopiedAt : a.numberOfCopies > b.numberOfCopies }
        }
    }
    public static func search(_ items: [ClipboardItem], query: String, mode: ClipboardSearch) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        func searchable(_ item: ClipboardItem) -> String { item.customTitle == nil ? item.title : item.title + "\n" + (item.text ?? "") }
        func exact() -> [ClipboardItem] { items.filter { searchable($0).localizedCaseInsensitiveContains(query) } }
        func regexp() -> [ClipboardItem] { items.filter { searchable($0).range(of: query, options: [.regularExpression, .caseInsensitive]) != nil } }
        func fuzzy() -> [ClipboardItem] {
            let fuse = Fuse(threshold: 0.7)
            let pattern = fuse.createPattern(from: query)
            return items.compactMap { item -> (Double, ClipboardItem)? in
                let title = String(searchable(item).prefix(5001))
                guard let result = fuse.search(pattern, in: title) else { return nil }
                return (result.score, item)
            }.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        switch mode { case .exact: return exact(); case .regexp: return regexp(); case .fuzzy: return fuzzy(); case .mixed: let a = exact(); if !a.isEmpty { return a }; let b = regexp(); return b.isEmpty ? fuzzy() : b }
    }
}

/// Attributes pending copies to the outgoing application before accepting a new
/// activation context. No workspace access: tests inject application identities.
@MainActor public final class ClipboardCaptureSession {
    private let pasteboard: NSPasteboard
    private var changeCount: Int
    public private(set) var application: String?
    public init(pasteboard: NSPasteboard, application: String?) {
        self.pasteboard = pasteboard; self.application = application; changeCount = pasteboard.changeCount
    }
    public var hasPendingChange: Bool { pasteboard.changeCount != changeCount }
    public func synchronize() { changeCount = pasteboard.changeCount }
    public func poll(preferences: ClipboardPreferences) -> ClipboardItem? {
        guard hasPendingChange else { return nil }; synchronize()
        return ClipboardCapture.read(pasteboard, application: application, preferences: preferences)
    }
    public func applicationDidActivate(_ incoming: String?, preferences: ClipboardPreferences) -> ClipboardItem? {
        let pending = poll(preferences: preferences)
        application = incoming
        return pending
    }
}

public struct ClipboardPasteTicket: Sendable {
    public let changeCount: Int
    public let targetProcessIdentifier: Int32
    public init(changeCount: Int, targetProcessIdentifier: Int32) { self.changeCount = changeCount; self.targetProcessIdentifier = targetProcessIdentifier }
    @MainActor public func isValid(pasteboard: NSPasteboard, frontmostProcessIdentifier: Int32?) -> Bool {
        pasteboard.changeCount == changeCount && frontmostProcessIdentifier == targetProcessIdentifier
    }
}

/// Queue completion changes metadata only. Clipboard preparation belongs to an
/// explicit next action, because posting paste keys does not acknowledge that
/// the target application has consumed the pasteboard bytes.
public struct ClipboardPasteQueue: Sendable {
    public private(set) var itemIDs: [UUID]
    private var preparedTicket: ClipboardPasteTicket?
    public init(itemIDs: [UUID] = []) { self.itemIDs = itemIDs }
    public mutating func prepare(ticket: ClipboardPasteTicket) { preparedTicket = ticket }
    @MainActor public mutating func complete(pasteboard: NSPasteboard, frontmostProcessIdentifier: Int32?) -> Bool {
        guard !itemIDs.isEmpty, let ticket = preparedTicket, ticket.isValid(pasteboard: pasteboard, frontmostProcessIdentifier: frontmostProcessIdentifier) else { return false }
        itemIDs.removeFirst(); preparedTicket = nil
        return true
    }
}
