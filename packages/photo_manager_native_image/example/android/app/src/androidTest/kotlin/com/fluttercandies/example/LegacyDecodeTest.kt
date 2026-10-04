package com.fluttercandies.example

import android.content.ContentUris
import android.content.ContentValues
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.fluttercandies.photo_manager_native_image.NativeImageDecoder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** MediaStore decode paths used on API 26–28, on real sample media. */
@Suppress("DEPRECATION")
@RunWith(AndroidJUnit4::class)
class LegacyDecodeTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val decoder = NativeImageDecoder(context)
    private val created = mutableListOf<Pair<File, Uri>>()

    @Before
    fun setUp() {
        assumeTrue(Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
    }

    @After
    fun tearDown() {
        created.forEach { (file, uri) ->
            context.contentResolver.delete(uri, null, null)
            file.delete()
        }
    }

    private fun scan(file: File): Uri {
        val latch = CountDownLatch(1)
        var result: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), null) { _, uri ->
            result = uri
            latch.countDown()
        }
        assertTrue("media scan timed out", latch.await(20, TimeUnit.SECONDS))
        return result!!.also { created.add(file to it) }
    }

    /**
     * A 400x300 landscape JPEG registered in MediaStore. `rotated` sets the
     * orientation column the decoder reads (90), as the scanner does for EXIF 6.
     */
    private fun landscapeJpeg(rotated: Boolean): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        dir.mkdirs()
        val file = File(dir, "pmni_${System.nanoTime()}.jpg")
        val bitmap = Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(0xFF2E7D32.toInt())
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        bitmap.recycle()
        val uri = scan(file)
        if (rotated) {
            val values = ContentValues().apply { put(MediaStore.Images.ImageColumns.ORIENTATION, 90) }
            assertEquals(1, context.contentResolver.update(uri, values, null, null))
        }
        return ContentUris.parseId(uri).toString()
    }

    private fun landscapeVideoRotated90(): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        dir.mkdirs()
        val file = File(dir, "pmni_${System.nanoTime()}.mp4")
        instrumentation.context.assets.open("landscape_rot90.mp4").use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        return ContentUris.parseId(scan(file)).toString()
    }

    @Test
    fun imageThumbnailIsUpright() {
        val id = landscapeJpeg(rotated = true)
        val bitmap = decoder.decode(id, 128, 128, isVideo = false)
        assertTrue("expected portrait, got ${bitmap.width}x${bitmap.height}", bitmap.height > bitmap.width)
        assertEquals(128, minOf(bitmap.width, bitmap.height))
        assertEquals(Bitmap.Config.ARGB_8888, bitmap.config)
    }

    @Test
    fun imageFullDecodeIsUpright() {
        // Above the MINI_KIND size, so this goes through BitmapFactory.
        val id = landscapeJpeg(rotated = true)
        val bitmap = decoder.decode(id, 512, 512, isVideo = false)
        assertEquals(300, bitmap.width)
        assertEquals(400, bitmap.height)
    }

    @Test
    fun imageWithoutRotationStaysLandscape() {
        val id = landscapeJpeg(rotated = false)
        val bitmap = decoder.decode(id, 512, 512, isVideo = false)
        assertEquals(400, bitmap.width)
        assertEquals(300, bitmap.height)
    }

    @Test
    fun videoThumbnailIsUpright() {
        val id = landscapeVideoRotated90()
        val bitmap = decoder.decode(id, 96, 96, isVideo = true)
        assertNotNull(bitmap)
        assertTrue("expected portrait, got ${bitmap.width}x${bitmap.height}", bitmap.height > bitmap.width)
    }
}
