import SwiftUI
import MuesliCore

struct MeetingFolderColorOption: Identifiable {
    let id: String
    let labelKey: L10nKey
    let hex: String?

    var swatchColor: Color {
        guard let hex else { return MuesliTheme.accent }
        return meetingFolderColor(from: hex) ?? MuesliTheme.accent
    }
}

enum MeetingFolderColors {
    static let all: [MeetingFolderColorOption] = [
        MeetingFolderColorOption(id: "none", labelKey: .sidebarFolderNoColor, hex: nil),
        MeetingFolderColorOption(id: "red", labelKey: .sidebarFolderColorRed, hex: "ff3b30"),
        MeetingFolderColorOption(id: "orange", labelKey: .sidebarFolderColorOrange, hex: "ff9500"),
        MeetingFolderColorOption(id: "yellow", labelKey: .sidebarFolderColorYellow, hex: "ffcc00"),
        MeetingFolderColorOption(id: "green", labelKey: .sidebarFolderColorGreen, hex: "34c759"),
        MeetingFolderColorOption(id: "blue", labelKey: .sidebarFolderColorBlue, hex: "007aff"),
        MeetingFolderColorOption(id: "purple", labelKey: .sidebarFolderColorPurple, hex: "af52de"),
        MeetingFolderColorOption(id: "pink", labelKey: .sidebarFolderColorPink, hex: "ff2d55"),
        MeetingFolderColorOption(id: "brown", labelKey: .sidebarFolderColorBrown, hex: "a2845e"),
    ]

    static func color(for folder: MeetingFolder?, fallback: Color = MuesliTheme.accent) -> Color {
        guard let hex = folder?.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return fallback
        }
        return meetingFolderColor(from: hex) ?? fallback
    }

    static func normalizedHex(_ hex: String?) -> String? {
        let trimmed = hex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard normalized.count == 6, UInt64(normalized, radix: 16) != nil else { return nil }
        return normalized.lowercased()
    }

}

private func meetingFolderColor(from hex: String) -> Color? {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
        return nil
    }
    return Color(hex: value)
}
