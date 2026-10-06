package com.fluttercandies.photo_manager_native_image

import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Point
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.FileNotFoundException

private val SRGB: ColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)

class NativeImageException(val code: String, message: String) : Exception(message)

/** Produces an upright `ARGB_8888` bitmap for a MediaStore id. */
class NativeImageDecoder(private val context: Context) {
    private val resolver: ContentResolver get() = context.contentResolver

    fun decode(assetId: String, width: Int, height: Int, isVideo: Boolean): Bitmap {
        val id = assetId.toLongOrNull()
            ?: throw NativeImageException("not_found", "Not a MediaStore id: $assetId")
        val uri = ContentUris.withAppendedId(
            if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            id,
        )
        val bitmap = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                decodeQ(uri, width, height, isVideo)
            } else {
                decodeLegacy(id, uri, width, height, isVideo)
            }
        } catch (e: FileNotFoundException) {
            throw NativeImageException("not_found", e.message ?: "Asset not found")
        } catch (e: NativeImageException) {
            throw e
        } catch (e: Exception) {
            throw NativeImageException("decode_failed", e.toString())
        }
        return ensureArgb8888(downscale(bitmap, width, height))
    }

    // MARK: API 29+

    @TargetApi(Build.VERSION_CODES.Q)
    private fun decodeQ(uri: Uri, width: Int, height: Int, isVideo: Boolean): Bitmap {
        if (isVideo || maxOf(width, height) <= ThumbnailMath.SYSTEM_THUMBNAIL_MAX) {
            val thumbnail = decodeSystemThumbnail(uri, width, height)
            if (isVideo || minOf(thumbnail.width, thumbnail.height) >= minOf(width, height)) return thumbnail
            thumbnail.recycle()
        }
        return decodeOriginal(uri, width, height)
    }

    /**
     * `ContentResolver.loadThumbnail` without its fit-inside-the-box sampling,
     * decoded straight to the target size in sRGB.
     */
    @TargetApi(Build.VERSION_CODES.Q)
    private fun decodeSystemThumbnail(uri: Uri, width: Int, height: Int): Bitmap {
        val opts = Bundle().apply { putParcelable(ContentResolver.EXTRA_SIZE, Point(width, height)) }
        var orientation = 0
        val source = ImageDecoder.createSource {
            val afd = resolver.openTypedAssetFileDescriptor(uri, "image/*", opts, null)
                ?: throw FileNotFoundException(uri.toString())
            orientation = afd.extras?.getInt(DocumentsContract.EXTRA_ORIENTATION, 0) ?: 0
            afd
        }
        val bitmap = decodeToTarget(source, width, height)
        if (orientation == 0) return bitmap
        val matrix = Matrix().apply { postRotate(orientation.toFloat()) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun decodeOriginal(uri: Uri, width: Int, height: Int): Bitmap =
        decodeToTarget(ImageDecoder.createSource(resolver, uri), width, height)

    /** Flutter's raw image descriptor reads pixels as sRGB, so wide-gamut sources are converted. */
    @TargetApi(Build.VERSION_CODES.Q)
    private fun decodeToTarget(source: ImageDecoder.Source, width: Int, height: Int): Bitmap =
        ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
            decoder.setTargetColorSpace(SRGB)
            ThumbnailMath.scaledSize(info.size.width, info.size.height, width, height)
                ?.let { (w, h) -> decoder.setTargetSize(w, h) }
        }

    // MARK: API 26–28

    private fun decodeLegacy(id: Long, uri: Uri, width: Int, height: Int, isVideo: Boolean): Bitmap {
        val targetShorter = minOf(width, height)
        return if (isVideo) decodeLegacyVideo(id, uri, width, height, targetShorter)
        else decodeLegacyImage(id, uri, targetShorter)
    }

    /**
     * Video frames from MINI_KIND thumbnails and MediaMetadataRetriever already
     * carry the rotation metadata on API 26–28, so no rotation is applied here.
     */
    @Suppress("DEPRECATION")
    private fun decodeLegacyVideo(id: Long, uri: Uri, width: Int, height: Int, targetShorter: Int): Bitmap {
        if (targetShorter <= ThumbnailMath.MINI_KIND_SHORTER) {
            MediaStore.Video.Thumbnails.getThumbnail(resolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null)
                ?.let { return it }
        }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(-1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, width, height)
            } else {
                retriever.getFrameAtTime(-1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            }
            return frame ?: throw NativeImageException("decode_failed", "No frame for $uri")
        } finally {
            retriever.release()
        }
    }

    /** Image thumbnails and BitmapFactory decodes ignore EXIF on API 26–28; MediaStore's orientation is applied. */
    @Suppress("DEPRECATION")
    private fun decodeLegacyImage(id: Long, uri: Uri, targetShorter: Int): Bitmap {
        val (sourceWidth, sourceHeight, rotation) = legacyImageMetadata(uri)
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inPreferredColorSpace = SRGB
        }
        var bitmap: Bitmap? = null
        if (targetShorter <= ThumbnailMath.MINI_KIND_SHORTER) {
            bitmap = MediaStore.Images.Thumbnails.getThumbnail(resolver, id, MediaStore.Images.Thumbnails.MINI_KIND, options)
        }
        if (bitmap == null) {
            bitmap = SampledBitmapDecoder.decode(resolver, uri, targetShorter)
                ?: throw NativeImageException("decode_failed", "No thumbnail for $uri")
        }
        val degrees = ThumbnailMath.rotationToApply(rotation, sourceWidth, sourceHeight, bitmap.width, bitmap.height)
        if (degrees == 0) return bitmap
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    /** `(width, height, rotationDegrees)` of an image as MediaStore reports it. */
    @SuppressLint("InlinedApi")
    @Suppress("DEPRECATION")
    private fun legacyImageMetadata(uri: Uri): Triple<Int, Int, Int> {
        val projection = arrayOf(
            MediaStore.Images.ImageColumns.WIDTH,
            MediaStore.Images.ImageColumns.HEIGHT,
            MediaStore.Images.ImageColumns.ORIENTATION,
        )
        resolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return Triple(cursor.getInt(0), cursor.getInt(1), cursor.getInt(2))
        }
        return Triple(0, 0, 0)
    }

    // MARK: Shared

    private fun downscale(bitmap: Bitmap, width: Int, height: Int): Bitmap {
        val target = ThumbnailMath.scaledSize(bitmap.width, bitmap.height, width, height) ?: return bitmap
        val scaled = Bitmap.createScaledBitmap(bitmap, target.first, target.second, true)
        if (scaled !== bitmap) bitmap.recycle()
        return scaled
    }

    private fun ensureArgb8888(bitmap: Bitmap): Bitmap {
        if (bitmap.config == Bitmap.Config.ARGB_8888) return bitmap
        val copy = bitmap.copy(Bitmap.Config.ARGB_8888, false)
            ?: throw NativeImageException("decode_failed", "Could not convert to ARGB_8888")
        bitmap.recycle()
        return copy
    }
}
