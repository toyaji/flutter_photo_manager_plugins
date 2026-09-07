package com.fluttercandies.photo_manager_native_image

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger

class RequestRegistryTest {
    private fun state(id: Long, sink: (Result<NativeImageReply?>) -> Unit = {}) = RequestState(id, sink)

    @Test
    fun finishDeliversExactlyOnce() {
        var replies = 0
        val s = state(1) { replies++ }
        assertTrue(s.finish(Result.success(null)))
        assertFalse(s.finish(Result.success(mapOf("pointer" to 1L))))
        assertFalse(s.finish(Result.failure(NativeImageError("decode_failed"))))
        assertEquals(1, replies)
        assertTrue(s.isDone)
    }

    @Test
    fun cancelBeforeAllocationMarksState() {
        val registry = RequestRegistry()
        val s = state(7)
        assertTrue(registry.register(s))
        registry.cancel(7)
        assertTrue(s.isCancelled)
        assertEquals(0, registry.cancelledAheadCount)
    }

    @Test
    fun cancelAheadOfRequestIsConsumedOnce() {
        val registry = RequestRegistry()
        registry.cancel(3)
        assertEquals(1, registry.cancelledAheadCount)
        assertFalse(registry.register(state(3)))
        assertEquals(0, registry.cancelledAheadCount)
        assertTrue(registry.register(state(3)))
    }

    @Test
    fun cancelAfterRemovalDoesNotResurrectRequest() {
        val registry = RequestRegistry()
        val s = state(9)
        assertTrue(registry.register(s))
        registry.remove(9)
        registry.cancel(9)
        assertFalse(s.isCancelled)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun cancelledAheadSetIsBounded() {
        val registry = RequestRegistry()
        for (id in 0 until (RequestRegistry.CANCELLED_AHEAD_LIMIT + 5).toLong()) registry.cancel(id)
        assertTrue(registry.cancelledAheadCount <= RequestRegistry.CANCELLED_AHEAD_LIMIT)
    }

    @Test
    fun cancelAllDrainsPending() {
        val registry = RequestRegistry()
        val a = state(1)
        val b = state(2)
        registry.register(a)
        registry.register(b)
        val drained = registry.cancelAll()
        assertEquals(2, drained.size)
        assertTrue(a.isCancelled && b.isCancelled)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun concurrentFinishDeliversOnce() {
        val replies = AtomicInteger()
        val s = state(5) { replies.incrementAndGet() }
        val start = CountDownLatch(1)
        val threads = (0 until 16).map {
            Thread {
                start.await()
                s.finish(Result.success(null))
            }.apply { start() }
        }
        start.countDown()
        threads.forEach { it.join() }
        assertEquals(1, replies.get())
    }
}
