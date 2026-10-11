package com.famgpslink.famgpslink

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!context.getSharedPreferences("tracking", Context.MODE_PRIVATE).getBoolean("wanted", false)) return
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED) return
        try { ContextCompat.startForegroundService(context, Intent(context, LocationService::class.java)) }
        catch (_: Exception) { /* Android may require a user-initiated reopen. */ }
    }
}
