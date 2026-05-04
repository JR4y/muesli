import Foundation
import MuesliCore

extension AppConfig {
    /// Build the sync-relevant snapshot from the current config. The
    /// `folderRemoteIDLookup` resolves local folder ids to their Supabase
    /// UUIDs; folders without a mapping are dropped from `folderOrderRemoteIDs`
    /// so they can be back-filled on a later sync cycle once they have a
    /// remote_id.
    func syncPreferencesSnapshot(folderRemoteIDLookup: (Int64) -> String?) -> SyncPreferencesSnapshot {
        let templates = AppConfigSyncCodec.encode(customMeetingTemplates) ?? "[]"
        let words = AppConfigSyncCodec.encode(customWords) ?? "[]"
        let folderRemoteIDs = folderOrder.compactMap(folderRemoteIDLookup)
        return SyncPreferencesSnapshot(
            customMeetingTemplatesJSON: templates,
            hiddenBuiltInTemplateIDs: hiddenBuiltInTemplateIDs,
            customWordsJSON: words,
            defaultMeetingTemplateID: defaultMeetingTemplateID,
            autoTemplateTargetID: autoTemplateTargetID,
            meetingTitlePrompt: meetingTitlePrompt,
            folderOrderRemoteIDs: folderRemoteIDs
        )
    }

    /// Returns a copy of `self` with sync-relevant fields replaced by the
    /// snapshot's values. Non-sync fields (API keys, hotkey, model picks,
    /// onboarding state, etc.) are preserved verbatim.
    func applyingSyncSnapshot(
        _ snapshot: SyncPreferencesSnapshot,
        folderLocalIDLookup: (String) -> Int64?
    ) -> AppConfig {
        var copy = self
        if let templates: [CustomMeetingTemplate] = AppConfigSyncCodec.decode(
            snapshot.customMeetingTemplatesJSON
        ) {
            copy.customMeetingTemplates = templates
        }
        copy.hiddenBuiltInTemplateIDs = snapshot.hiddenBuiltInTemplateIDs
        if let words: [CustomWord] = AppConfigSyncCodec.decode(
            snapshot.customWordsJSON
        ) {
            copy.customWords = words
        }
        copy.defaultMeetingTemplateID = snapshot.defaultMeetingTemplateID
        copy.autoTemplateTargetID = snapshot.autoTemplateTargetID
        copy.meetingTitlePrompt = snapshot.meetingTitlePrompt
        copy.folderOrder = snapshot.folderOrderRemoteIDs.compactMap(folderLocalIDLookup)
        return copy
    }
}

enum AppConfigSyncCodec {
    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func decode<T: Decodable>(_ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
