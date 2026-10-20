package com.vtq.app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Álbum de fotos de VitaQ en la galería del teléfono (Pictures/VitaQ).
 *
 * Todo el trabajo de disco va en hilos de fondo y cualquier fallo vuelve a Dart
 * como error del canal: nada de lo que pase aquí debe cerrar la app.
 */
class PhotoGalleryChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "vtq/gallery")
    private val main = Handler(Looper.getMainLooper())

    // Guardar en orden (un hilo); miniaturas y lecturas en paralelo.
    private val writer = Executors.newSingleThreadExecutor()
    private val readers = Executors.newFixedThreadPool(2)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        writer.shutdown()
        readers.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Antes de Android 10 escribir en Pictures exige el permiso de almacenamiento.
            "needsStoragePermission" -> result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
            "save" -> runAsync(writer, result) {
                save(call.argument<String>("path")!!, call.argument<String>("name")!!)
            }
            "list" -> runAsync(readers, result) { list() }
            "thumbnail" -> runAsync(readers, result) {
                thumbnail(Uri.parse(call.argument<String>("uri")!!), call.argument<Int>("size") ?: 256)
            }
            "read" -> runAsync(readers, result) { read(Uri.parse(call.argument<String>("uri")!!)) }
            else -> result.notImplemented()
        }
    }

    private fun runAsync(executor: ExecutorService, result: MethodChannel.Result, work: () -> Any?) {
        try {
            executor.execute {
                try {
                    val value = work()
                    main.post { result.success(value) }
                } catch (e: Throwable) {
                    Log.e(TAG, "gallery error", e)
                    main.post { result.error(e.javaClass.simpleName, e.message, null) }
                }
            }
        } catch (e: Throwable) {
            result.error(e.javaClass.simpleName, e.message, null)
        }
    }

    // ------------------------------------------------------------------ guardar

    private fun save(path: String, name: String): Map<String, Any> {
        val source = File(path)
        require(source.isFile && source.length() > 0) { "La foto está vacía" }
        val takenAt = System.currentTimeMillis()

        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveScoped(source, name, takenAt)
        } else {
            saveLegacy(source, name, takenAt)
        }
        return mapOf("uri" to uri.toString(), "name" to name, "takenAt" to takenAt)
    }

    private fun saveScoped(source: File, name: String, takenAt: Long): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.DATE_TAKEN, takenAt)
            put(MediaStore.Images.Media.RELATIVE_PATH, RELATIVE_PATH)
            // Oculta hasta terminar de escribir: la galería nunca ve una foto a medias.
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: error("No se pudo crear la foto en la galería")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(source).use { it.copyTo(out) }
            } ?: error("No se pudo escribir la foto")
            resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
            return uri
        } catch (e: Throwable) {
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(source: File, name: String, takenAt: Long): Uri {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ALBUM)
        if (!dir.isDirectory && !dir.mkdirs()) error("No se pudo crear la carpeta $dir")
        val target = File(dir, name)
        source.copyTo(target, overwrite = true)

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DATA, target.absolutePath)
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.DATE_TAKEN, takenAt)
        }
        val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        if (uri == null) {
            // Que la galería la encuentre de todos modos.
            MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf("image/jpeg"), null)
            return Uri.fromFile(target)
        }
        return uri
    }

    // ------------------------------------------------------------------- leer

    /** Fotos del álbum, la más reciente primero. */
    @Suppress("DEPRECATION")
    private fun list(): List<Map<String, Any>> {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED,
        )
        val (selection, args) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.Images.Media.RELATIVE_PATH} = ?" to arrayOf(RELATIVE_PATH)
        } else {
            "${MediaStore.Images.Media.DATA} LIKE ?" to arrayOf("%/${Environment.DIRECTORY_PICTURES}/$ALBUM/%")
        }
        val order = "${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC"

        val photos = mutableListOf<Map<String, Any>>()
        context.contentResolver.query(collection, projection, selection, args, order)?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val takenCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val addedCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val takenAt = if (c.isNull(takenCol)) c.getLong(addedCol) * 1000 else c.getLong(takenCol)
                photos += mapOf(
                    "uri" to ContentUris.withAppendedId(collection, id).toString(),
                    "name" to (c.getString(nameCol) ?: ""),
                    "takenAt" to takenAt,
                )
            }
        }
        return photos
    }

    private fun thumbnail(uri: Uri, size: Int): ByteArray {
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && uri.scheme == "content") {
            context.contentResolver.loadThumbnail(uri, Size(size, size), null)
        } else {
            decodeSampled(uri, size)
        }
        try {
            return ByteArrayOutputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                out.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun decodeSampled(uri: Uri, size: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        open(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= size && bounds.outHeight / (sample * 2) >= size) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return open(uri).use { BitmapFactory.decodeStream(it, null, options) }
            ?: error("No se pudo leer la foto")
    }

    private fun read(uri: Uri): ByteArray = open(uri).use { it.readBytes() }

    private fun open(uri: Uri) =
        context.contentResolver.openInputStream(uri) ?: error("No se pudo abrir la foto")

    companion object {
        private const val TAG = "VtqGallery"
        const val ALBUM = "VitaQ"
        private val RELATIVE_PATH = "${Environment.DIRECTORY_PICTURES}/$ALBUM/"
    }
}
