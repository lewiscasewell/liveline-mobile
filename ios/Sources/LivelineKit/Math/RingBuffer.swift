import Foundation

/// A fixed-capacity circular buffer. Once warm (after the first `capacity`
/// pushes) it performs **no allocation on write** — new elements overwrite the
/// oldest slot in place. This is what the render loop reads from every frame.
///
/// Logical index `0` is always the oldest retained element; `count - 1` is the
/// newest.
public struct RingBuffer<Element> {
    private var storage: ContiguousArray<Element>
    /// Storage index of the oldest logical element.
    private var start: Int
    /// The maximum number of elements retained.
    public let capacity: Int

    /// The number of elements currently held (`0...capacity`).
    public private(set) var count: Int

    /// Creates an empty buffer that retains at most `capacity` elements.
    ///
    /// Backing storage is reserved up front so that pushes during warm-up do
    /// not reallocate.
    /// - Parameter capacity: Maximum retained elements. Must be greater than 0.
    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = ContiguousArray<Element>()
        self.storage.reserveCapacity(capacity)
        self.start = 0
        self.count = 0
    }

    /// `true` when the buffer holds `capacity` elements.
    public var isFull: Bool { count == capacity }
    /// `true` when the buffer holds no elements.
    public var isEmpty: Bool { count == 0 }

    /// Appends `element`, evicting the oldest element if the buffer is full.
    ///
    /// After warm-up this overwrites an existing slot and allocates nothing.
    public mutating func push(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
            count += 1
        } else {
            storage[start] = element
            start = (start + 1) % capacity
        }
    }

    /// Replaces the newest element in place. No-op if empty.
    public mutating func replaceLast(_ element: Element) {
        guard count > 0 else { return }
        storage[(start + count - 1) % capacity] = element
    }

    /// The newest element, or `nil` if empty.
    public var last: Element? {
        guard count > 0 else { return nil }
        return self[count - 1]
    }

    /// The oldest element, or `nil` if empty.
    public var first: Element? {
        guard count > 0 else { return nil }
        return self[0]
    }

    /// Reads the element at logical index `i` (0 = oldest).
    public subscript(_ i: Int) -> Element {
        precondition(i >= 0 && i < count, "RingBuffer index out of range")
        return storage[(start + i) % capacity]
    }

    /// Removes all elements without releasing the reserved storage.
    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        start = 0
        count = 0
    }

    /// Applies `body` to each element from oldest to newest. Allocation-free.
    public func forEach(_ body: (Element) -> Void) {
        for i in 0..<count {
            body(storage[(start + i) % capacity])
        }
    }

    /// A snapshot of the buffer contents, oldest first. Allocates — for tests
    /// and backfill, not the hot path.
    public var elements: [Element] {
        var out = [Element]()
        out.reserveCapacity(count)
        forEach { out.append($0) }
        return out
    }
}

extension RingBuffer: Sendable where Element: Sendable {}
