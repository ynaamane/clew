import Foundation

/// The meeting list row's meta line — date, duration, voice count, e.g.
/// "27 juil. 15:36 · 17:30 · 3 voix" (mockup.html:272). Delegates to MeetingHeaderDetail, which
/// already composes the same facts for the detail header, rather than re-implementing the join
/// and the absent-never-zero rule. The row differs from the header in exactly one way: it never
/// shows the language, so it always calls through with an empty language.
public enum MeetingRowMeta {
    public static func text(date: String, duration: TimeInterval?, speakerCount: Int?) -> String {
        MeetingHeaderDetail.text(date: date, duration: duration, language: "", speakerCount: speakerCount)
    }
}
