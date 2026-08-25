package com.liveline.core

/**
 * A fixed-capacity circular buffer. Once warm (after the first [capacity]
 * pushes) it performs **no allocation on write** — new elements overwrite the
 * oldest slot in place. This is what the render loop reads from every frame.
 *
 * Logical index `0` is always the oldest retained element; `count - 1` is the
 * newest.
 */
class RingBuffer<E>(val capacity: Int) {
    init { require(capacity > 0) { "RingBuffer capacity must be > 0" } }

    private val storage = ArrayList<E>(capacity)
    /** Storage index of the oldest logical element. */
    private var start = 0

    /** The number of elements currently held (`0..capacity`). */
    var count = 0
        private set

    /** `true` when the buffer holds [capacity] elements. */
    val isFull: Boolean get() = count == capacity
    /** `true` when the buffer holds no elements. */
    val isEmpty: Boolean get() = count == 0

    /** Appends [element], evicting the oldest if full. Allocation-free once warm. */
    fun push(element: E) {
        if (storage.size < capacity) {
            storage.add(element)
            count += 1
        } else {
            storage[start] = element
            start = (start + 1) % capacity
        }
    }

    /** Replaces the newest element in place. No-op if empty. */
    fun replaceLast(element: E) {
        if (count == 0) return
        storage[(start + count - 1) % capacity] = element
    }

    /** The newest element, or `null` if empty. */
    val last: E? get() = if (count == 0) null else this[count - 1]
    /** The oldest element, or `null` if empty. */
    val first: E? get() = if (count == 0) null else this[0]

    /** Reads the element at logical index [i] (0 = oldest). */
    operator fun get(i: Int): E {
        require(i in 0 until count) { "RingBuffer index out of range" }
        return storage[(start + i) % capacity]
    }

    /** Removes all elements without releasing the reserved storage. */
    fun removeAll() {
        storage.clear()
        start = 0
        count = 0
    }

    /** Applies [body] to each element from oldest to newest. */
    fun forEach(body: (E) -> Unit) {
        for (i in 0 until count) body(this[i])
    }

    /** A snapshot of the contents, oldest first. Allocates — for tests/backfill. */
    val elements: List<E>
        get() = ArrayList<E>(count).also { out -> for (i in 0 until count) out.add(this[i]) }
}
