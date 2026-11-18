package com.fluttercandies.photo_manager_native_image

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Pure sizing and rotation rules shared by the decoders; unit-tested. */
object ThumbnailMath {
    /**
     * Largest image size for which the MediaStore system thumbnail is tried before the original.
     * The system thumbnail is a recompressed JPEG, so above this size it looks soft next to
     * the same size decoded from the original.
     */
    const val SYSTEM_THUMBNAIL_MAX = 256

    /**
     * Largest video size for which the system thumbnail is used, even when it is smaller than
     * asked. The system thumbnail and [NativeImageDecoder]'s own frame can be different frames,
     * so mixing the two for one video swaps the picture between sizes.
     */
    const val SYSTEM_VIDEO_THUMBNAIL_MAX = 768

    /** Shorter side of a `MINI_KIND` thumbnail (512x384) in the worst case. */
    const val MINI_KIND_SHORTER = 384

    /** Decoded pixels are capped at this many target squares, so panoramas stay bounded. */
    const val MAX_PIXELS_IN_TARGET_SQUARES = 4

    /**
     * Size that scales `width x height` so its shorter side equals
     * `min(targetWidth, targetHeight)`, then shrinks further until the area is
     * at most [MAX_PIXELS_IN_TARGET_SQUARES] target squares. Never upscales;
     * `null` when the image already fits.
     */
    fun scaledSize(width: Int, height: Int, targetWidth: Int, targetHeight: Int): Pair<Int, Int>? {
        if (width <= 0 || height <= 0) return null
        val targetShorter = min(targetWidth, targetHeight).toDouble()
        val shorter = min(width, height)
        var scale = if (shorter > targetShorter) targetShorter / shorter else 1.0
        val maxPixels = MAX_PIXELS_IN_TARGET_SQUARES * targetShorter * targetShorter
        val pixels = width * scale * height * scale
        if (pixels > maxPixels) scale *= sqrt(maxPixels / pixels)
        if (scale >= 1.0) return null
        return Pair(max(1, (width * scale).roundToInt()), max(1, (height * scale).roundToInt()))
    }

    /**
     * Box to pass to `MediaMetadataRetriever.getScaledFrameAtTime` so the
     * frame, which is fitted inside the box, comes out at [scaledSize] of the
     * upright video. The longer side gets one extra pixel so rounding never
     * makes the box limit the shorter side.
     */
    fun videoFrameBox(
        videoWidth: Int,
        videoHeight: Int,
        rotationDegrees: Int,
        targetWidth: Int,
        targetHeight: Int,
    ): Pair<Int, Int>? {
        if (videoWidth <= 0 || videoHeight <= 0) return null
        val quarterTurn = (((rotationDegrees % 360) + 360) % 360) % 180 == 90
        val width = if (quarterTurn) videoHeight else videoWidth
        val height = if (quarterTurn) videoWidth else videoHeight
        val (w, h) = scaledSize(width, height, targetWidth, targetHeight) ?: Pair(width, height)
        return if (w >= h) Pair(w + 1, h) else Pair(w, h + 1)
    }

    /** Whether the MediaStore system thumbnail is tried before decoding the source. */
    fun triesSystemThumbnail(targetWidth: Int, targetHeight: Int, isVideo: Boolean): Boolean =
        max(targetWidth, targetHeight) <= if (isVideo) SYSTEM_VIDEO_THUMBNAIL_MAX else SYSTEM_THUMBNAIL_MAX

    /**
     * Whether a system thumbnail of `width x height` is returned as is. A video keeps it even
     * when it is smaller than asked, so that every size of one video shows the same frame.
     */
    fun keepsSystemThumbnail(width: Int, height: Int, targetWidth: Int, targetHeight: Int, isVideo: Boolean): Boolean =
        isVideo || coversTarget(width, height, targetWidth, targetHeight)

    /** Whether a decoded `width x height` reaches the requested shorter side. */
    fun coversTarget(width: Int, height: Int, targetWidth: Int, targetHeight: Int): Boolean =
        min(width, height) >= min(targetWidth, targetHeight)

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
