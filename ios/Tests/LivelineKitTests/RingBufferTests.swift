import XCTest

@testable import LivelineKit

final class RingBufferTests: XCTestCase {
    func testFillsUpToCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        XCTAssertTrue(buffer.isEmpty)
        buffer.push(1)
        buffer.push(2)
        XCTAssertEqual(buffer.count, 2)
        XCTAssertFalse(buffer.isFull)
        buffer.push(3)
        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.elements, [1, 2, 3])
    }

    func testEvictsOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { buffer.push(i) }
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.elements, [3, 4, 5])
        XCTAssertEqual(buffer.first, 3)
        XCTAssertEqual(buffer.last, 5)
    }

    func testSubscriptIsOldestFirst() {
        var buffer = RingBuffer<Int>(capacity: 4)
        for i in 10...15 { buffer.push(i) }
        // Retains 12,13,14,15
        XCTAssertEqual(buffer[0], 12)
        XCTAssertEqual(buffer[3], 15)
    }

    func testRemoveAllResets() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.push(1)
        buffer.push(2)
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.first)
        XCTAssertNil(buffer.last)
        buffer.push(9)
        XCTAssertEqual(buffer.elements, [9])
    }

    func testForEachOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for i in 1...4 { buffer.push(i) }
        var seen = [Int]()
        buffer.forEach { seen.append($0) }
        XCTAssertEqual(seen, [2, 3, 4])
    }
}
