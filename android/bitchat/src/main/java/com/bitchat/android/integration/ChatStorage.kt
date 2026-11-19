package com.bitchat.android.integration

import android.content.Context
import java.io.File

internal val Context.chatCacheDir: File
    get() = File(cacheDir, "bitchat").apply { mkdirs() }

internal val Context.chatFilesDir: File
    get() = File(filesDir, "bitchat").apply { mkdirs() }
