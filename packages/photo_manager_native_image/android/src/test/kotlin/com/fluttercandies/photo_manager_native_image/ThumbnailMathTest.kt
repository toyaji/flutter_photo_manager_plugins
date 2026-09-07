package com.fluttercandies.photo_manager_native_image

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ThumbnailMathTest {
    @Test
    fun scaledSizeMatchesShorterSideWithoutUpscaling() {
        assertEquals(Pair(427, 320), ThumbnailMath.scaledSize(640, 480, 320, 320))
        assertEquals(Pair(320, 427), ThumbnailMath.scaledSize(480, 640, 320, 320))
        assertNull(ThumbnailMath.scaledSize(300, 200, 320, 320))
        assertNull(ThumbnailMath.scaledSize(320, 320, 320, 320))
    }

    @Test
    fun sampleSizeKeepsShorterSideAtLeastTarget() {
        assertEquals(1, ThumbnailMath.sampleSize(400, 300, 320))
        assertEquals(2, ThumbnailMath.sampleSize(4000, 700, 320))
        assertEquals(8, ThumbnailMath.sampleSize(4000, 3000, 320))
        assertEquals(16, ThumbnailMath.sampleSize(8000, 6000, 320))
    }

    @Test
    fun rotationIsAppliedToUnrotatedThumbnails() {
        // Landscape source, landscape thumbnail, EXIF 90: still needs rotating.
        assertEquals(90, ThumbnailMath.rotationToApply(90, 4000, 3000, 512, 384))
        assertEquals(270, ThumbnailMath.rotationToApply(270, 4000, 3000, 512, 384))
        assertEquals(180, ThumbnailMath.rotationToApply(180, 4000, 3000, 512, 384))
        assertEquals(0, ThumbnailMath.rotationToApply(0, 4000, 3000, 512, 384))
    }

    @Test
    fun rotationIsSkippedWhenThumbnailIsAlreadyUpright() {
        // Landscape source, portrait thumbnail: the framework already rotated.
        assertEquals(0, ThumbnailMath.rotationToApply(90, 4000, 3000, 384, 512))
        assertEquals(0, ThumbnailMath.rotationToApply(270, 1920, 1080, 270, 480))
    }

    @Test
    fun rotationFallsBackToMetadataForSquareOrUnknownSources() {
        assertEquals(90, ThumbnailMath.rotationToApply(90, 1000, 1000, 100, 100))
        assertEquals(90, ThumbnailMath.rotationToApply(90, 0, 0, 512, 384))
        assertEquals(90, ThumbnailMath.rotationToApply(-270, 4000, 3000, 512, 384))
        assertEquals(0, ThumbnailMath.rotationToApply(45, 4000, 3000, 512, 384))
    }
}
