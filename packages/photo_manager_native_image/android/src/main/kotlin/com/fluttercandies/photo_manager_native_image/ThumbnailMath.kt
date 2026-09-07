package com.fluttercandies.photo_manager_native_image

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Pure sizing and rotation rules shared by the decoders; unit-tested. */
object ThumbnailMath {
    /** Largest size `ContentResolver.loadThumbnail` is asked for directly. */
    const val LOAD_THUMBNAIL_MAX = 768

    /** Shorter side of a `MINI_KIND` thumbnail (512x384) in the worst case. */
    const val MINI_KIND_SHORTER = 384

    /**
     * Size that scales `width x height` so its shorter side equals
     * `min(targetWidth, targetHeight)`, never upscaling. `null` when the
     * image is already small enough.
     */
    fun scaledSize(width: Int, height: Int, targetWidth: Int, targetHeight: Int): Pair<Int, Int>? {
        val shorter = min(width, height)
        val targetShorter = min(targetWidth, targetHeight)
        if (shorter <= targetShorter || shorter <= 0) return null
        val scale = targetShorter.toDouble() / shorter
        return Pair(max(1, (width * scale).roundToInt()), max(1, (height * scale).roundToInt()))
    }

    /**
     * Power-of-two `BitmapFactory.Options.inSampleSize` that keeps the
     * decoded shorter side at or above `targetShorter`.
     */
    fun sampleSize(width: Int, height: Int, targetShorter: Int): Int {
        var sample = 1
        val shorter = min(width, height)
        while (shorter / (sample * 2) >= targetShorter) {
            sample *= 2
        }
        return sample
    }

    /**
     * Degrees to apply to a pre-Q thumbnail whose source reports
     * [rotationDegrees]. The framework sometimes already rotated the bitmap;
     * a 90/270 rotation that already flipped the aspect is detected and
     * skipped so it is never applied twice.
     */
    fun rotationToApply(
        rotationDegrees: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        thumbWidth: Int,
        thumbHeight: Int,
    ): Int {
        val normalized = ((rotationDegrees % 360) + 360) % 360
        if (normalized == 0) return 0
        if (normalized == 180) return 180
        if (normalized != 90 && normalized != 270) return 0
        if (sourceWidth <= 0 || sourceHeight <= 0 || sourceWidth == sourceHeight) return normalized
        val sourceLandscape = sourceWidth > sourceHeight
        val thumbLandscape = thumbWidth > thumbHeight
        return if (sourceLandscape == thumbLandscape) normalized else 0
    }
}
