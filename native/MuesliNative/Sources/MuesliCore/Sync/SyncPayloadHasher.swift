import Foundation
import CryptoKit

/// Builds canonical JSON payloads for sync entities and produces a stable
/// SHA-256 hex digest. The resulting hash is used to detect spurious
/// "different version, identical content" conflicts.
public enum SyncPayloadHasher {

    public static func dictationHash(
        timestamp: String,
        durationSeconds: Double,
        rawText: String,
        appContext: String,
        wordCount: Int,
        source: String,
        startedAt: String?,
        endedAt: String?
    ) -> String {
        let payload: [String: Any] = [
            "timestamp": timestamp,
            "duration_seconds": roundedForHash(durationSeconds),
            "raw_text": rawText,
            "app_context": appContext,
            "word_count": wordCount,
            "source": source,
            "started_at": startedAt as Any? ?? NSNull(),
            "ended_at": endedAt as Any? ?? NSNull(),
        ]
        return hash(payload)
    }

    public static func meetingHash(
        title: String,
        calendarEventID: String?,
        calendarEventSnapshotJSON: String?,
        startTime: String,
        endTime: String?,
        durationSeconds: Double?,
        rawTranscript: String,
        formattedNotes: String,
        meetingStatus: String,
        manualNotes: String,
        wordCount: Int,
        selectedTemplateID: String?,
        selectedTemplateName: String?,
        selectedTemplateKind: String?,
        selectedTemplatePrompt: String?,
        folderRemoteID: String?
    ) -> String {
        let snapshot: Any = canonicalizeJSON(calendarEventSnapshotJSON) ?? NSNull()
        let payload: [String: Any] = [
            "title": title,
            "calendar_event_id": calendarEventID as Any? ?? NSNull(),
            "calendar_event_snapshot": snapshot,
            "start_time": startTime,
            "end_time": endTime as Any? ?? NSNull(),
            "duration_seconds": durationSeconds.map(roundedForHash) as Any? ?? NSNull(),
            "raw_transcript": rawTranscript,
            "formatted_notes": formattedNotes,
            "meeting_status": meetingStatus,
            "manual_notes": manualNotes,
            "word_count": wordCount,
            "selected_template_id": selectedTemplateID as Any? ?? NSNull(),
            "selected_template_name": selectedTemplateName as Any? ?? NSNull(),
            "selected_template_kind": selectedTemplateKind as Any? ?? NSNull(),
            "selected_template_prompt": selectedTemplatePrompt as Any? ?? NSNull(),
            "folder_remote_id": folderRemoteID as Any? ?? NSNull(),
        ]
        return hash(payload)
    }

    public static func folderHash(
        name: String,
        parentRemoteID: String?,
        colorHex: String?,
        iconName: String?,
        sortOrder: Int
    ) -> String {
        let payload: [String: Any] = [
            "name": name,
            "parent_folder_remote_id": parentRemoteID as Any? ?? NSNull(),
            "color_hex": colorHex as Any? ?? NSNull(),
            "icon_name": iconName as Any? ?? NSNull(),
            "sort_order": sortOrder,
        ]
        return hash(payload)
    }

    public static func preferencesHash(_ snapshot: SyncPreferencesSnapshot) -> String {
        let templates: Any = canonicalizeJSON(snapshot.customMeetingTemplatesJSON) ?? []
        let words: Any = canonicalizeJSON(snapshot.customWordsJSON) ?? []
        let payload: [String: Any] = [
            "custom_meeting_templates": templates,
            "hidden_built_in_template_ids": snapshot.hiddenBuiltInTemplateIDs,
            "custom_words": words,
            "default_meeting_template_id": snapshot.defaultMeetingTemplateID,
            "auto_template_target_id": snapshot.autoTemplateTargetID,
            "meeting_title_prompt": snapshot.meetingTitlePrompt,
            "folder_order_remote_ids": snapshot.folderOrderRemoteIDs,
        ]
        return hash(payload)
    }

    // MARK: - Internals

    private static func hash(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            return ""
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Re-parses the given JSON string so nested objects sort their keys when
    /// the outer payload is re-serialized with `.sortedKeys`. Returns nil if
    /// the input is nil/empty/invalid.
    private static func canonicalizeJSON(_ raw: String?) -> Any? {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func roundedForHash(_ value: Double) -> Double {
        // Three decimals is enough granularity to compare durations across
        // devices without false-positive conflicts from float drift.
        (value * 1000).rounded() / 1000
    }
}
