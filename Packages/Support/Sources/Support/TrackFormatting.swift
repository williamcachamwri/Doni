import Foundation

/// File sizes the way a Telegram row prints them.
///
/// `DefaultPresentationStrings.swift:72-97` divides by 1024 and prints *one floored* decimal
/// digit, so 1 572 864 bytes is "1,5 MB" and never "1,6". Its kilobyte branch divides the
/// remainder by 102 rather than 102.4, which can disagree with the other two by a tenth of a
/// kilobyte; the difference only ever shows on files under 1 MB, so this follows the uniform
/// rule instead of the artefact.
public enum DataSize {
    public static func string(
        _ bytes: Int64,
        decimalSeparator: String = Locale.current.decimalSeparator ?? "."
    ) -> String {
        let kilobyte: Int64 = 1024
        let megabyte = kilobyte * 1024
        let gigabyte = megabyte * 1024

        if bytes >= gigabyte {
            return formatted(bytes, unit: gigabyte, suffix: "GB", decimalSeparator: decimalSeparator)
        } else if bytes >= megabyte {
            return formatted(bytes, unit: megabyte, suffix: "MB", decimalSeparator: decimalSeparator)
        } else if bytes >= kilobyte {
            return formatted(bytes, unit: kilobyte, suffix: "KB", decimalSeparator: decimalSeparator)
        }
        return "\(bytes) B"
    }

    private static func formatted(
        _ bytes: Int64,
        unit: Int64,
        suffix: String,
        decimalSeparator: String
    ) -> String {
        let whole = bytes / unit
        let tenth = bytes % unit * 10 / unit
        guard tenth != 0 else { return "\(whole) \(suffix)" }
        return "\(whole)\(decimalSeparator)\(tenth) \(suffix)"
    }

    private static func separator() -> String {
        Locale.current.decimalSeparator ?? "."
    }
}

/// A duration in the timestamp slot.
///
/// `StringForDuration.swift:3-19`: minutes and seconds are `%d:%02d`, and an hour adds a third
/// group rather than rolling the minutes over.
public enum MediaClock {
    public static func duration(_ seconds: Int?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let rest = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }
}
