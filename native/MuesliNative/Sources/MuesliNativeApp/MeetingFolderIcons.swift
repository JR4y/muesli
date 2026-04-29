import Foundation
import MuesliCore

struct MeetingFolderIconOption: Identifiable, Hashable {
    let symbolName: String

    var id: String { symbolName }
}

enum MeetingFolderIcons {
    static let all: [MeetingFolderIconOption] = [
        MeetingFolderIconOption(symbolName: "folder.fill"),
        MeetingFolderIconOption(symbolName: "briefcase.fill"),
        MeetingFolderIconOption(symbolName: "building.2.fill"),
        MeetingFolderIconOption(symbolName: "person.2.fill"),
        MeetingFolderIconOption(symbolName: "tag.fill"),
        MeetingFolderIconOption(symbolName: "bookmark.fill"),
        MeetingFolderIconOption(symbolName: "doc.text.fill"),
        MeetingFolderIconOption(symbolName: "doc.richtext.fill"),
        MeetingFolderIconOption(symbolName: "terminal.fill"),
        MeetingFolderIconOption(symbolName: "hammer.fill"),
        MeetingFolderIconOption(symbolName: "wrench.and.screwdriver.fill"),
        MeetingFolderIconOption(symbolName: "shippingbox.fill"),
        MeetingFolderIconOption(symbolName: "archivebox.fill"),
        MeetingFolderIconOption(symbolName: "chart.bar.fill"),
        MeetingFolderIconOption(symbolName: "bolt.fill"),
        MeetingFolderIconOption(symbolName: "bubble.left.and.bubble.right.fill"),
        MeetingFolderIconOption(symbolName: "megaphone.fill"),
        MeetingFolderIconOption(symbolName: "globe"),
        MeetingFolderIconOption(symbolName: "link"),
        MeetingFolderIconOption(symbolName: "flag.fill"),
        MeetingFolderIconOption(symbolName: "star.fill"),
        MeetingFolderIconOption(symbolName: "books.vertical.fill"),
        MeetingFolderIconOption(symbolName: "tray.full.fill"),
        MeetingFolderIconOption(symbolName: "checklist"),
    ]

    static func resolvedIconName(for folder: MeetingFolder?) -> String {
        let trimmed = folder?.iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "folder.fill" : trimmed
    }

    static func normalized(_ iconName: String?) -> String? {
        let trimmed = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return all.contains(where: { $0.symbolName == trimmed }) ? trimmed : nil
    }
}
