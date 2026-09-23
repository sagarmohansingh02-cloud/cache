import Foundation

/// "Just now", "23 min ago", "Yesterday", "Sep 3" — how long ago, the way a
/// person would say it.
enum RelativeTime {
    static func string(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return "Just now" }
        if seconds < 3_600 { return "\(max(1, Int((seconds / 60).rounded()))) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) hr ago" }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return "Yesterday" }
        if days < 7 { return "\(days) days ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
