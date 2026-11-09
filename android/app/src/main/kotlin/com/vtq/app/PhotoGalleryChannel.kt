package com.vtq.app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
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
 * Álbum de fotos y videos de VitaQ en la galería del teléfono (Pictures/VitaQ).
 * Los videos van en la misma carpeta: MediaStore admite videos en Pictures, y así
 * la galería del teléfono muestra un solo álbum VitaQ.
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
        val isVideo = name.endsWith(".mp4", ignoreCase = true)
        require(source.isFile && source.length() > 0) { if (isVideo) "El video está vacío" else "La foto está vacía" }
        // Un MP4 sin cerrar (sin índice) no se puede reproducir: mejor fallar y que
        // Dart lo vuelva a intentar cuando la cámara termine de cerrarlo.
        val durationMs = if (isVideo) videoDuration(source) else 0L
        val takenAt = System.currentTimeMillis()
        val kind = if (isVideo) VIDEO else IMAGE

        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveScoped(source, name, takenAt, kind)
        } else {
            saveLegacy(source, name, takenAt, kind)
        }
        return item(uri, name, takenAt, isVideo, durationMs)
    }

    private fun videoDuration(file: File): Long {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val ms = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            require(ms != null && ms > 0) { "El video está incompleto" }
            return ms
        } catch (e: RuntimeException) {
            throw IllegalStateException("El video está incompleto", e)
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun saveScoped(source: File, name: String, takenAt: Long, kind: Kind): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, kind.mime)
            put(MediaStore.MediaColumns.DATE_TAKEN, takenAt)
            put(MediaStore.MediaColumns.RELATIVE_PATH, RELATIVE_PATH)
            // Oculta hasta terminar de escribir: la galería nunca ve un archivo a medias.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(kind.scopedCollection(), values)
            ?: error("No se pudo crear el archivo en la galería")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(source).use { it.copyTo(out) }
            } ?: error("No se pudo escribir el archivo")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            return uri
        } catch (e: Throwable) {
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(source: File, name: String, takenAt: Long, kind: Kind): Uri {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ALBUM)
        if (!dir.isDirectory && !dir.mkdirs()) error("No se pudo crear la carpeta $dir")
        val target = File(dir, name)
        source.copyTo(target, overwrite = true)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DATA, target.absolutePath)
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, kind.mime)
            put(MediaStore.Images.Media.DATE_TAKEN, takenAt)
        }
        val uri = context.contentResolver.insert(kind.legacyCollection, values)
        if (uri == null) {
            // Que la galería lo encuentre de todos modos.
            MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf(kind.mime), null)
            return Uri.fromFile(target)
        }
        return uri
    }

    private fun item(uri: Uri, name: String, takenAt: Long, isVideo: Boolean, durationMs: Long) = mapOf(
        "uri" to uri.toString(),
        "name" to name,
        "takenAt" to takenAt,
        "isVideo" to isVideo,
        "durationMs" to durationMs,
    )

    /** Fotos o videos: cada uno vive en su propia colección de MediaStore. */
    private class Kind(
        val mime: String,
        val legacyCollection: Uri,
        val scopedCollection: () -> Uri,
    )

    // ------------------------------------------------------------------- leer

    /** Fotos y videos del álbum, el más reciente primero. */
    private fun list(): List<Map<String, Any>> =
        (query(IMAGE, isVideo = false) + query(VIDEO, isVideo = true))
            .sortedByDescending { it.first }
            .map { it.second }

    /** Elementos de una colección, con su hora de guardado para ordenarlos. */
    @Suppress("DEPRECATION")
    private fun query(kind: Kind, isVideo: Boolean): List<Pair<Long, Map<String, Any>>> {
        val collection = kind.legacyCollection
        val projection = mutableListOf<String>().apply {
            add(MediaStore.MediaColumns._ID)
            add(MediaStore.MediaColumns.DISPLAY_NAME)
            add(MediaStore.Images.Media.DATE_TAKEN)
            add(MediaStore.MediaColumns.DATE_ADDED)
            if (isVideo) add(MediaStore.Video.Media.DURATION)
        }.toTypedArray()
        val (selection, args) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?" to arrayOf(RELATIVE_PATH)
        } else {
            "${MediaStore.MediaColumns.DATA} LIKE ?" to arrayOf("%/${Environment.DIRECTORY_PICTURES}/$ALBUM/%")
        }

        val items = mutableListOf<Pair<Long, Map<String, Any>>>()
        context.contentResolver.query(collection, projection, selection, args, null)?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val takenCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val addedCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val durationCol = if (isVideo) c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION) else -1
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val addedAt = c.getLong(addedCol) * 1000
                val takenAt = if (c.isNull(takenCol)) addedAt else c.getLong(takenCol)
                val durationMs = if (durationCol >= 0 && !c.isNull(durationCol)) c.getLong(durationCol) else 0L
                val uri = ContentUris.withAppendedId(collection, id)
                items += takenAt to item(uri, c.getString(nameCol) ?: "", takenAt, isVideo, durationMs)
            }
        }
        return items
    }

    private fun thumbnail(uri: Uri, size: Int): ByteArray {
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && uri.scheme == "content") {
            context.contentResolver.loadThumbnail(uri, Size(size, size), null)
        } else if (isVideoUri(uri)) {
            videoFrame(uri, size)
        } else {
            decodeSampled(uri, size)
        }
        try {
            return ByteArrayOutputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)
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

    @Suppress("DEPRECATION")
    private fun isVideoUri(uri: Uri) =
        uri.toString().startsWith(MediaStore.Video.Media.EXTERNAL_CONTENT_URI.toString()) ||
            uri.path?.endsWith(".mp4", ignoreCase = true) == true

    /** Primer cuadro de un video, reducido a unos [size] píxeles (Android 9 o anterior). */
    private fun videoFrame(uri: Uri, size: Int): Bitmap {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val frame = retriever.frameAtTime ?: error("No se pudo leer el video")
            val scale = size.toFloat() / maxOf(frame.width, frame.height)
            if (scale >= 1f) return frame
            val small = Bitmap.createScaledBitmap(
                frame, maxOf(1, (frame.width * scale).toInt()), maxOf(1, (frame.height * scale).toInt()), true,
            )
            if (small !== frame) frame.recycle()
            return small
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun read(uri: Uri): ByteArray = open(uri).use { it.readBytes() }

    private fun open(uri: Uri) =
        context.contentResolver.openInputStream(uri) ?: error("No se pudo abrir la foto")

    companion object {
        private const val TAG = "VtqGallery"
        const val ALBUM = "VitaQ"
        private val RELATIVE_PATH = "${Environment.DIRECTORY_PICTURES}/$ALBUM/"

        @Suppress("DEPRECATION")
        private val IMAGE = Kind("image/jpeg", MediaStore.Images.Media.EXTERNAL_CONTENT_URI) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }

        @Suppress("DEPRECATION")
        private val VIDEO = Kind("video/mp4", MediaStore.Video.Media.EXTERNAL_CONTENT_URI) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
    }
}
