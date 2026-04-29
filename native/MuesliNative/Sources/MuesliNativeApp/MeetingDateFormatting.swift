import Foundation

enum MeetingDateFormatting {
    private static let isoParsers: [ISO8601DateFormatter] = {
        let isoWithFractionalSeconds = ISO8601DateFormatter()
        isoWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        return [isoWithFractionalSeconds, iso]
    }()

    private static let localParsers: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter
        }
    }()

    private static let meetingTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let compactMeetingTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        isoParsers.lazy.compactMap { $0.date(from: raw) }.first
            ?? localParsers.lazy.compactMap { $0.date(from: raw) }.first
    }

    static func formatMeetingTimestamp(_ raw: String) -> String {
        guard let date = parse(raw) else {
            let clean = raw.replacingOccurrences(of: "T", with: " ")
            return clean.count > 16 ? String(clean.prefix(16)) : clean
        }
        return meetingTimestampFormatter.string(from: date)
    }

    static func formatCompactMeetingTimestamp(_ raw: String) -> String {
        guard let date = parse(raw) else {
            return formatMeetingTimestamp(raw)
        }
        return compactMeetingTimestampFormatter.string(from: date)
    }
}
