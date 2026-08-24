import XCTest

@testable import LivelineKit

final class IntervalsTests: XCTestCase {
    func testMatchesReferenceTable() {
        XCTAssertEqual(Intervals.niceTimeInterval(windowSecs: 10), 2)
        XCTAssertEqual(Intervals.niceTimeInterval(windowSecs: 30), 5)
        XCTAssertEqual(Intervals.niceTimeInterval(windowSecs: 60), 10)
        XCTAssertEqual(Intervals.niceTimeInterval(windowSecs: 300), 30)
        XCTAssertEqual(Intervals.niceTimeInterval(windowSecs: 3600), 600)
        XCTAssertEqual(Intervals.niceTimeInterval(windowSecs: 86400), 7200)
    }

    func testBeyondWeekIsWeek() {
        XCTAssertEqual(Intervals.niceTimeInterval(windowSecs: 2_000_000), 604800)
    }
}
