package com.fluttercandies.photo_manager_native_image

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class PhotoManagerNativeImagePlugin : FlutterPlugin, NativeImageHostApi {
    private lateinit var decoder: NativeImageDecoder
    private val registry = RequestRegistry()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService =
        Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors() / 2 + 1)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        decoder = NativeImageDecoder(binding.applicationContext)
        NativeImageHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeImageHostApi.setUp(binding.binaryMessenger, null)
        registry.cancelAll().forEach { it.finish(Result.success(null)) }
        executor.shutdownNow()
    }

    override fun requestImage(
        assetId: String,
        requestId: Long,
        width: Long,
        height: Long,
        isVideo: Boolean,
        allowNetwork: Boolean,
        callback: (Result<NativeImageReply?>) -> Unit,
    ) {
        // Replies must be posted from the main thread.
        val state = RequestState(requestId) { result -> mainHandler.post { callback(result) } }
        if (!registry.register(state)) {
            state.finish(Result.success(null))
            return
        }
        try {
            executor.execute {
                val result = produce(state, assetId, width.toInt(), height.toInt(), isVideo)
                registry.remove(requestId)
                state.finish(result)
            }
        } catch (_: Exception) {
            registry.remove(requestId)
            state.finish(Result.success(null))
        }
    }

    override fun cancelRequest(requestId: Long) {
        registry.cancel(requestId)
    }

    private fun produce(
        state: RequestState, assetId: String, width: Int, height: Int, isVideo: Boolean,
    ): Result<NativeImageReply?> {
        if (state.isCancelled) return Result.success(null)
        val bitmap = try {
            decoder.decode(assetId, width, height, isVideo)
        } catch (e: NativeImageException) {
            return Result.failure(NativeImageError(e.code, e.message))
        }
        if (state.isCancelled) {
            bitmap.recycle()
            return Result.success(null)
        }
        // No cancel checks past this point: the buffer is Dart's to free.
        return try {
            Result.success(copyToNativeBuffer(bitmap))
        } catch (e: Exception) {
            Result.failure(NativeImageError("decode_failed", e.toString()))
        } finally {
            bitmap.recycle()
        }
    }

    private fun copyToNativeBuffer(bitmap: Bitmap): NativeImageReply {
        val rowBytes = bitmap.rowBytes
        val size = rowBytes.toLong() * bitmap.height
        val pointer = NativeBuffer.allocate(size)
        if (pointer == 0L) throw IllegalStateException("malloc($size) failed")
        try {
            bitmap.copyPixelsToBuffer(NativeBuffer.wrap(pointer, size))
        } catch (e: Exception) {
            NativeBuffer.free(pointer)
            throw e
        }
        return mapOf(
            "pointer" to pointer,
            "width" to bitmap.width.toLong(),
            "height" to bitmap.height.toLong(),
            "rowBytes" to rowBytes.toLong(),
        )
    }
}
