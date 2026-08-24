import Foundation

/// Picks a nice time-axis tick interval in seconds for a given visible window,
/// extending web liveline's `niceTimeInterval` up through months and years so a
/// multi-timeframe chart (30 min → 4 years) labels sensibly.
public enum Intervals {
    /// The tick spacing, in seconds, for a window of `windowSecs` seconds.
    public static func niceTimeInterval(windowSecs: Double) -> Double {
        let minute = 60.0
        let hour = 3600.0
        let day = 86400.0
        let week = 604800.0
        let month = 2_592_000.0  // 30 days
        let year = 31_536_000.0  // 365 days

        if windowSecs <= 15 { return 2 }
        if windowSecs <= 30 { return 5 }
        if windowSecs <= 60 { return 10 }
        if windowSecs <= 120 { return 15 }
        if windowSecs <= 300 { return 30 }
        if windowSecs <= 600 { return minute }
        if windowSecs <= 1800 { return 5 * minute }
        if windowSecs <= hour { return 10 * minute }
        if windowSecs <= 4 * hour { return 30 * minute }
        if windowSecs <= 12 * hour { return hour }
        if windowSecs <= day { return 2 * hour }
        if windowSecs <= 3 * day { return 6 * hour }
        if windowSecs <= week { return day }
        if windowSecs <= month { return week }
        if windowSecs <= 3 * month { return 2 * week }
        if windowSecs <= year { return month }
        if windowSecs <= 2 * year { return 3 * month }  // quarters
        return year
    }
}
