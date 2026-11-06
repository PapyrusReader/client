package com.papyrus.reader

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val appUpdates by lazy { AppUpdates(this) }
    private val folderRequest = 7142
    private var folderResult: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cursors = mutableMapOf<String, FolderCursor>()
    private val grants by lazy { getSharedPreferences("papyrus-folder-grants", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdates.configure(flutterEngine)
        TimerNotifications.configure(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "papyrus/folders").setMethodCallHandler { call, result ->
            if (call.method == "pick") {
                if (folderResult != null) {
                    result.error("busy", "A folder picker is already open.", null)
                } else {
                    folderResult = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }, folderRequest)
                    } catch (error: Exception) {
                        folderResult = null
                        result.error("unavailable", "The system folder picker is unavailable.", null)
                    }
                }
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val key = call.argument<String>("grant")
                    val tree = key?.let { grants.getString(it, null)?.let(Uri::parse) }
                    fun requireTree(): Uri = tree ?: throw SecurityException("Reconnect this folder to allow access.")
                    val value: Any? = when (call.method) {
                        "restore" -> {
                            val uri = requireTree()
                            contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
                        }
                        "start" -> {
                            val uri = requireTree()
                            val cursor = UUID.randomUUID().toString()
                            cursors[cursor] = FolderCursor(uri, call.argument<Boolean>("recursive") == true)
                            cursor
                        }
                        "next" -> cursors[call.argument<String>("cursor")]?.next() ?: emptyList<Any>()
                        "close" -> { cursors.remove(call.argument<String>("cursor"))?.close(); null }
                        "stat" -> {
                            val uri = DocumentsContract.buildDocumentUriUsingTree(requireTree(), call.argument<String>("key")!!)
                            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                                if (!cursor.moveToFirst()) throw java.io.FileNotFoundException("Source file unavailable offline.")
                                metadata(cursor)
                            } ?: throw java.io.FileNotFoundException("Source file unavailable offline.")
                        }
                        "read" -> {
                            val uri = DocumentsContract.buildDocumentUriUsingTree(requireTree(), call.argument<String>("key")!!)
                            contentResolver.openInputStream(uri)?.use { it.readBytes() }
                                ?: throw java.io.FileNotFoundException("Source file unavailable offline.")
                        }
                        "release" -> {
                            if (key != null && !grants.edit().remove(key).commit()) {
                                throw java.io.IOException("Could not release folder permission.")
                            }
                            if (tree != null && grants.all.values.none { it == tree.toString() }) {
                                try {
                                    contentResolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                } catch (_: SecurityException) { }
                            }
                            null
                        }
                        else -> throw IllegalArgumentException("Unknown folder operation.")
                    }
                    main.post { result.success(value) }
                } catch (error: Exception) {
                    val code = if (error is SecurityException) "access" else "unavailable"
                    main.post { result.error(code, error.message ?: "Could not access this folder.", null) }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        TimerNotifications.opened(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        TimerNotifications.detach(flutterEngine)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == TimerNotifications.permissionRequest) TimerNotifications.refresh(this, true)
    }

    @Deprecated("Activity result bridge for Flutter folder access")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != folderRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = folderResult
        folderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result?.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val document = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            val name = contentResolver.query(document, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "Book folder"
            val key = UUID.randomUUID().toString()
            if (!grants.edit().putString(key, uri.toString()).commit()) throw java.io.IOException("Could not save folder permission.")
            result?.success(mapOf("key" to key, "identity" to uri.toString(), "name" to name, "location" to name, "persistent" to true))
        } catch (error: Exception) {
            if (grants.all.values.none { it == uri.toString() }) {
                try {
                    contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: SecurityException) { }
            }
            result?.error("access", "Could not keep access to this folder. Select a permitted subfolder.", null)
        }
    }

    override fun onResume() {
        super.onResume()
        appUpdates.resumeUpdate()
    }

    override fun onDestroy() {
        worker.execute {
            cursors.values.forEach { it.close() }
            cursors.clear()
        }
        worker.shutdown()
        super.onDestroy()
    }

    private val projection = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_SIZE,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED
    )

    private fun metadata(cursor: Cursor): Map<String, Any> = mapOf(
        "key" to cursor.getString(0), "name" to cursor.getString(1),
        "size" to (if (cursor.isNull(3)) -1L else cursor.getLong(3)),
        "modified" to (if (cursor.isNull(4)) 0L else cursor.getLong(4))
    )

    private inner class FolderCursor(private val tree: Uri, private val recursive: Boolean) {
        private val directories = ArrayDeque<String>().apply { add(DocumentsContract.getTreeDocumentId(tree)) }
        private var current: Cursor? = null

        fun next(): List<Map<String, Any>> {
            val batch = mutableListOf<Map<String, Any>>()
            while (batch.size < 128) {
                if (current == null) {
                    if (directories.isEmpty()) break
                    val directory = directories.removeFirst()
                    val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, directory)
                    try {
                        current = contentResolver.query(uri, projection, null, null, null)
                            ?: throw java.io.FileNotFoundException("Folder unavailable. Reconnect the drive or folder.")
                    } catch (error: Exception) {
                        if (directory == DocumentsContract.getTreeDocumentId(tree)) throw error
                        batch.add(mapOf("key" to directory, "name" to directory.substringAfterLast('/'),
                            "size" to 0L, "modified" to 0L, "error" to (error.message ?: "Could not read this subfolder.")))
                        continue
                    }
                }
                val cursor = current!!
                if (!cursor.moveToNext()) { cursor.close(); current = null; continue }
                val name = cursor.getString(1)
                if (name.startsWith(".") || name.startsWith("~") || Regex("\\.(tmp|part|partial|crdownload|download)$", RegexOption.IGNORE_CASE).containsMatchIn(name)) continue
                if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                    if (recursive) directories.add(cursor.getString(0))
                } else {
                    batch.add(metadata(cursor))
                }
            }
            return batch
        }

        fun close() { current?.close(); current = null; directories.clear() }
    }
}
