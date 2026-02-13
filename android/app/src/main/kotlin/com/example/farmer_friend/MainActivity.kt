// MainActivity.kt
package com.example.farmer_friend

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL = "farmer_friend/media_scanner"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("NO_PATH", "No path provided", null)
                        return@setMethodCallHandler
                    }
                    scanFile(applicationContext, path) {
                        result.success(true)
                    }
                }

                "saveToGallery" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("NO_PATH", "No path provided", null)
                        return@setMethodCallHandler
                    }

                    val mimeFromDart = call.argument<String>("mime")
                    val mime = mimeFromDart ?: guessMimeType(path)

                    val savedUri = saveFileToGallery(applicationContext, path, mime)
                    if (savedUri != null) {
                        result.success(savedUri.toString())
                    } else {
                        result.error("SAVE_FAILED", "Failed to save to gallery", null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // --------- helpers ----------

    private fun scanFile(ctx: Context, path: String, onComplete: () -> Unit) {
        MediaScannerConnection.scanFile(ctx, arrayOf(path), null) { _, _ ->
            onComplete()
        }
    }

    private fun guessMimeType(path: String): String {
        val ext = MimeTypeMap.getFileExtensionFromUrl(path) ?: ""
        return if (ext.isNotEmpty()) {
            MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(ext.lowercase()) ?: "application/octet-stream"
        } else {
            "application/octet-stream"
        }
    }

    /**
     * Save a file into MediaStore so that it appears in Gallery.
     *  - Images go to Pictures/FarmRover
     *  - Videos go to Movies/FarmRover
     *  - Other files go to Download/FarmRover
     *
     * Returns content:// Uri or null on failure.
     */
    private fun saveFileToGallery(ctx: Context, sourcePath: String, mimeTypeRaw: String?): Uri? {
        try {
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) return null

            // Normalize MJPEG → a common video MIME so Gallery recognises it
            val mimeType = when (mimeTypeRaw?.lowercase()) {
                "video/x-mjpeg",
                "video/mjpg",
                "video/x-motion-jpeg" -> "video/mp4"
                else -> mimeTypeRaw
            }

            val isImage = mimeType?.startsWith("image") == true
            val isVideo = mimeType?.startsWith("video") == true

            // ---------------- Android 10+ (Q) ----------------
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = ctx.contentResolver

                val baseCollection: Uri = when {
                    isImage -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    isVideo -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    else    -> MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }

                val relativePath = when {
                    isImage -> "${Environment.DIRECTORY_PICTURES}/FarmRover"
                    isVideo -> "${Environment.DIRECTORY_MOVIES}/FarmRover"
                    else    -> "${Environment.DIRECTORY_DOWNLOADS}/FarmRover"
                }

                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, sourceFile.name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                }

                // Try insert into the main collection first
                var uri: Uri? = resolver.insert(baseCollection, values)

                // If inserting as video fails (some devices don't like uncommon types),
                // fall back to generic Files collection.
                if (uri == null && isVideo) {
                    val filesCollection =
                        MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    uri = resolver.insert(filesCollection, values)
                }

                if (uri == null) return null

                resolver.openOutputStream(uri).use { outStream ->
                    FileInputStream(sourceFile).use { inStream ->
                        if (outStream != null) {
                            inStream.copyTo(outStream)
                        }
                    }
                }

                // extra scan to refresh some gallery apps
                scanFile(ctx, sourceFile.absolutePath) {}

                return uri
            }

            // ---------------- Android 9 and below ----------------
            val dstDir: File = when {
                isImage -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                isVideo -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                else    -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            }

            val folder = File(dstDir, "FarmRover")
            if (!folder.exists()) folder.mkdirs()

            val dstFile = File(folder, sourceFile.name)
            FileInputStream(sourceFile).use { inStream ->
                dstFile.outputStream().use { outStream ->
                    inStream.copyTo(outStream)
                }
            }

            MediaScannerConnection.scanFile(ctx, arrayOf(dstFile.absolutePath), null) { _, _ -> }
            return Uri.fromFile(dstFile)

        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
}
