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
        MeetingFolderColorOption(id: "red", labelKey: .sidebarFolderColorRed, hex: "e03e3e"),
        MeetingFolderColorOption(id: "orange", labelKey: .sidebarFolderColorOrange, hex: "d9730d"),
        MeetingFolderColorOption(id: "yellow", labelKey: .sidebarFolderColorYellow, hex: "dfab01"),
        MeetingFolderColorOption(id: "green", labelKey: .sidebarFolderColorGreen, hex: "0f7b6c"),
        MeetingFolderColorOption(id: "blue", labelKey: .sidebarFolderColorBlue, hex: "337ea9"),
        MeetingFolderColorOption(id: "purple", labelKey: .sidebarFolderColorPurple, hex: "9065b0"),
        MeetingFolderColorOption(id: "pink", labelKey: .sidebarFolderColorPink, hex: "ad1a72"),
        MeetingFolderColorOption(id: "brown", labelKey: .sidebarFolderColorBrown, hex: "64473a"),
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
