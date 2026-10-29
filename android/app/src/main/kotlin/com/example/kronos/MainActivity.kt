package com.example.kronos

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var directoryPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cc.angius.kronos/backup_directory",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickBackupDirectory" -> {
                    if (directoryPickerResult != null) {
                        result.error("picker_busy", "A folder picker is already open.", null)
                        return@setMethodCallHandler
                    }

                    directoryPickerResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                        )
                    }
                    try {
                        startActivityForResult(intent, BACKUP_DIRECTORY_REQUEST)
                    } catch (exception: Exception) {
                        directoryPickerResult = null
                        result.error("picker_unavailable", exception.message, null)
                    }
                }

                "releaseBackupDirectory" -> {
                    try {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri != null) {
                            contentResolver.persistedUriPermissions
                                .filter { it.uri == uri }
                                .forEach { permission ->
                                    var flags = 0
                                    if (permission.isReadPermission) {
                                        flags = flags or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    }
                                    if (permission.isWritePermission) {
                                        flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                                    }
                                    if (flags != 0) {
                                        contentResolver.releasePersistableUriPermission(
                                            uri,
                                            flags,
                                        )
                                    }
                                }
                        }
                        result.success(null)
                    } catch (exception: Exception) {
                        result.error("directory_permission_release_failed", exception.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated by Android, retained for FlutterActivity result routing")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != BACKUP_DIRECTORY_REQUEST) return

        val result = directoryPickerResult ?: return
        directoryPickerResult = null
        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return
        }

        try {
            val grantFlags = (data?.flags ?: 0) and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, grantFlags)
            val documentId = DocumentsContract.getTreeDocumentId(uri)
            val name = Uri.decode(documentId.substringAfter(':').substringAfterLast('/'))
            result.success(mapOf("uri" to uri.toString(), "name" to name))
        } catch (exception: Exception) {
            result.error("directory_permission_failed", exception.message, null)
        }
    }

    private companion object {
        const val BACKUP_DIRECTORY_REQUEST = 48127
    }
}
