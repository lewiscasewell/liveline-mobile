package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RingBufferTest {
    @Test
    fun fillsUpToCapacity() {
        val buffer = RingBuffer<Int>(capacity = 3)
        assertTrue(buffer.isEmpty)
        buffer.push(1)
        buffer.push(2)
        assertEquals(2, buffer.count)
        assertFalse(buffer.isFull)
        buffer.push(3)
        assertTrue(buffer.isFull)
        assertEquals(listOf(1, 2, 3), buffer.elements)
    }

    @Test
    fun evictsOldestWhenFull() {
        val buffer = RingBuffer<Int>(capacity = 3)
        for (i in 1..5) buffer.push(i)
        assertEquals(3, buffer.count)
        assertEquals(listOf(3, 4, 5), buffer.elements)
        assertEquals(3, buffer.first)
        assertEquals(5, buffer.last)
    }

    @Test
    fun subscriptIsOldestFirst() {
        val buffer = RingBuffer<Int>(capacity = 4)
        for (i in 10..15) buffer.push(i)
        // Retains 12,13,14,15
        assertEquals(12, buffer[0])
        assertEquals(15, buffer[3])
    }

    @Test
    fun removeAllResets() {
        val buffer = RingBuffer<Int>(capacity = 3)
        buffer.push(1)
        buffer.push(2)
        buffer.removeAll()
        assertTrue(buffer.isEmpty)
        assertNull(buffer.first)
        assertNull(buffer.last)
        buffer.push(9)
        assertEquals(listOf(9), buffer.elements)
    }

    @Test
    fun forEachOrder() {
        val buffer = RingBuffer<Int>(capacity = 3)
        for (i in 1..4) buffer.push(i)
        val seen = mutableListOf<Int>()
        buffer.forEach { seen.add(it) }
        assertEquals(listOf(2, 3, 4), seen)
    }
}
