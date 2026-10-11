package com.famgpslink.famgpslink

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.firebase.FirebaseApp
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionReply: MethodChannel.Result? = null
    private val preferences get() = getSharedPreferences("tracking", MODE_PRIVATE)
    private fun granted(permission: String) = ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.famgpslink/location").setMethodCallHandler { call, reply ->
            when (call.method) {
                "status" -> {
                    val power = getSystemService(POWER_SERVICE) as PowerManager
                    val location = getSystemService(LOCATION_SERVICE) as LocationManager
                    reply.success(mapOf(
                        "foreground" to (granted(Manifest.permission.ACCESS_FINE_LOCATION) || granted(Manifest.permission.ACCESS_COARSE_LOCATION)),
                        "precise" to granted(Manifest.permission.ACCESS_FINE_LOCATION),
                        "background" to (Build.VERSION.SDK_INT < 29 || granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)),
                        "gpsEnabled" to (if (Build.VERSION.SDK_INT >= 28) location.isLocationEnabled else
                            location.isProviderEnabled(LocationManager.GPS_PROVIDER) || location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)),
                        "powerSave" to power.isPowerSaveMode,
                        "batteryOptimized" to !power.isIgnoringBatteryOptimizations(packageName),
                        "lastError" to (preferences.getString("lastError", "") ?: "")
                    ))
                }
                "requestForeground" -> {
                    if (permissionReply != null) reply.error("busy", "A permission request is already open.", null)
                    else {
                        permissionReply = reply
                        val permissions = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
                        if (Build.VERSION.SDK_INT >= 33) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
                        requestPermissions(permissions.toTypedArray(), 101)
                    }
                }
                "requestBackground" -> {
                    if (Build.VERSION.SDK_INT >= 30) {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        reply.success(null)
                    } else if (Build.VERSION.SDK_INT == 29 && permissionReply == null) {
                        permissionReply = reply
                        requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), 101)
                    } else reply.success(null)
                }
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    reply.success(null)
                }
                "start" -> {
                    val id = call.argument<String>("memberId")
                    if (id == null || FirebaseApp.getApps(this).isEmpty()) reply.error("setup", "Firebase is not configured.", null)
                    else if (!granted(Manifest.permission.ACCESS_FINE_LOCATION) && !granted(Manifest.permission.ACCESS_COARSE_LOCATION)) {
                        reply.error("permission", "Allow location access before enabling sharing.", null)
                    } else {
                        try {
                            preferences.edit().putString("memberId", id).putBoolean("wanted", true).apply()
                            ContextCompat.startForegroundService(this, Intent(this, LocationService::class.java))
                            reply.success(null)
                        } catch (_: Exception) { reply.error("background", "Open the app to resume background tracking.", null) }
                    }
                }
                "stop" -> {
                    preferences.edit().putBoolean("wanted", false).apply()
                    stopService(Intent(this, LocationService::class.java))
                    FixStore(this).clear()
                    reply.success(null)
                }
                "freshFix" -> {
                    if (!granted(Manifest.permission.ACCESS_FINE_LOCATION) && !granted(Manifest.permission.ACCESS_COARSE_LOCATION)) {
                        reply.error("permission", "Allow location access first. Your manual pin remains active.", null)
                    } else {
                        val request = CurrentLocationRequest.Builder().setPriority(Priority.PRIORITY_HIGH_ACCURACY)
                            .setMaxUpdateAgeMillis(0).setDurationMillis(30000).build()
                        LocationServices.getFusedLocationProviderClient(this).getCurrentLocation(request, CancellationTokenSource().token)
                            .addOnSuccessListener { fix ->
                                if (fix == null || System.currentTimeMillis() - fix.time > 60000) {
                                    reply.error("timeout", "No fresh GPS fix. Your manual pin remains active.", null)
                                } else reply.success(mapOf("latitude" to fix.latitude, "longitude" to fix.longitude,
                                    "accuracy" to fix.accuracy.toDouble(), "measuredAt" to fix.time))
                            }.addOnFailureListener { reply.error("location", "Could not obtain a fresh location. Check GPS and permissions.", null) }
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 101) { permissionReply?.success(null); permissionReply = null }
    }
}
