package com.fluttercandies.photo_manager_native_image

import android.annotation.SuppressLint
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import java.io.FileNotFoundException

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

    private fun decodeQ(uri: Uri, width: Int, height: Int, isVideo: Boolean): Bitmap {
        if (isVideo || maxOf(width, height) <= ThumbnailMath.LOAD_THUMBNAIL_MAX) {
            return resolver.loadThumbnail(uri, Size(width, height), null)
        }
        val source = ImageDecoder.createSource(resolver, uri)
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
            ThumbnailMath.scaledSize(info.size.width, info.size.height, width, height)
                ?.let { (w, h) -> decoder.setTargetSize(w, h) }
        }
    }

    // MARK: API 26–28

    @Suppress("DEPRECATION")
    private fun decodeLegacy(id: Long, uri: Uri, width: Int, height: Int, isVideo: Boolean): Bitmap {
        val targetShorter = minOf(width, height)
        val (sourceWidth, sourceHeight, rotation) = legacyMetadata(id, uri, isVideo)
        val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        var bitmap: Bitmap? = null
        if (targetShorter <= ThumbnailMath.MINI_KIND_SHORTER) {
            bitmap = if (isVideo) {
                MediaStore.Video.Thumbnails.getThumbnail(resolver, id, MediaStore.Video.Thumbnails.MINI_KIND, options)
            } else {
                MediaStore.Images.Thumbnails.getThumbnail(resolver, id, MediaStore.Images.Thumbnails.MINI_KIND, options)
            }
        }
        if (bitmap == null && !isVideo) {
            bitmap = decodeWithBitmapFactory(uri, targetShorter)
        }
        if (bitmap == null) {
            throw NativeImageException("decode_failed", "No thumbnail for $uri")
        }
        val degrees = ThumbnailMath.rotationToApply(rotation, sourceWidth, sourceHeight, bitmap.width, bitmap.height)
        if (degrees == 0) return bitmap
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    private fun decodeWithBitmapFactory(uri: Uri, targetShorter: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            ?: throw FileNotFoundException(uri.toString())
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = ThumbnailMath.sampleSize(bounds.outWidth, bounds.outHeight, targetShorter)
        }
        return resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
    }

    /** `(width, height, rotationDegrees)` of the source as MediaStore reports it. */
    @SuppressLint("InlinedApi")
    @Suppress("DEPRECATION")
    private fun legacyMetadata(id: Long, uri: Uri, isVideo: Boolean): Triple<Int, Int, Int> {
        val projection = if (isVideo) {
            arrayOf(MediaStore.Video.VideoColumns.WIDTH, MediaStore.Video.VideoColumns.HEIGHT)
        } else {
            arrayOf(
                MediaStore.Images.ImageColumns.WIDTH,
                MediaStore.Images.ImageColumns.HEIGHT,
                MediaStore.Images.ImageColumns.ORIENTATION,
            )
        }
        var width = 0
        var height = 0
        var rotation = 0
        resolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                width = cursor.getInt(0)
                height = cursor.getInt(1)
                if (!isVideo) rotation = cursor.getInt(2)
            }
        }
        if (isVideo) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, uri)
                rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
                if (width == 0 || height == 0) {
                    width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                    height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                }
            } catch (_: Exception) {
                // Rotation stays 0; the frame is still shown.
            } finally {
                retriever.release()
            }
        }
        return Triple(width, height, rotation)
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
