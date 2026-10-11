package com.famgpslink.famgpslink

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.location.Location
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.*
import org.json.JSONObject
import kotlin.math.min

class LocationService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val prefs get() = getSharedPreferences("tracking", MODE_PRIVATE)
    private lateinit var store: FixStore
    private lateinit var client: FusedLocationProviderClient
    private lateinit var state: DatabaseReference
    private var memberId = ""
    private var uid = ""
    private var revision = -1L
    private var connected = false
    private var uploading = false
    private var sharing = false
    private var overridden = true
    private var moving = true
    private var lastMotion = 0L
    private var anchor: Location? = null
    private var pending: JSONObject? = null
    private var retrySeconds = 5L
    @Volatile private var destroyed = false
    private val observers = mutableListOf<Pair<DatabaseReference, ValueEventListener>>()
    private var authObserver: FirebaseAuth.AuthStateListener? = null
    private val retry = Runnable { flush() }
    private val idle = Runnable { if (moving) { moving = false; requestUpdates() } }
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            if (destroyed) return
            val fix = result.lastLocation ?: return
            if (!sharing || overridden || fix.accuracy < 0 || System.currentTimeMillis() - fix.time > 60000) return
            val distance = anchor?.distanceTo(fix) ?: 100f
            if (fix.speed >= 0.8f || distance >= 50f) {
                anchor = fix
                lastMotion = System.currentTimeMillis()
                if (!moving) { moving = true; requestUpdates() }
                handler.removeCallbacks(idle)
                handler.postDelayed(idle, 180000)
            } else if (System.currentTimeMillis() - lastMotion > 180000 && moving) { moving = false; requestUpdates() }
            if (pending != null && fix.time <= pending!!.optLong("measuredAt")) return
            pending = JSONObject().put("latitude", fix.latitude).put("longitude", fix.longitude)
                .put("accuracy", fix.accuracy.toDouble()).put("measuredAt", fix.time)
                .put("revision", revision).put("uid", uid).put("memberId", memberId)
            store.save(pending.toString())
            flush()
        }
    }

    override fun onCreate() {
        super.onCreate()
        store = FixStore(this)
        client = LocationServices.getFusedLocationProviderClient(this)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("location", "Family location sharing", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        startForeground(31, NotificationCompat.Builder(this, "location").setSmallIcon(R.drawable.ic_location)
            .setContentTitle("FamGPSlink is sharing your location").setContentText("Tap to manage location sharing")
            .setContentIntent(open).setOngoing(true).setSilent(true).build())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (memberId.isNotEmpty()) return START_STICKY
        if (!prefs.getBoolean("wanted", false)) { stopSelf(); return START_NOT_STICKY }
        memberId = prefs.getString("memberId", "") ?: ""
        if (FirebaseApp.getApps(this).isEmpty()) FirebaseApp.initializeApp(this)
        val user = FirebaseAuth.getInstance().currentUser
        if (user == null || memberId.isEmpty()) { stopSelf(); return START_NOT_STICKY }
        uid = user.uid
        val db = FirebaseDatabase.getInstance()
        state = db.getReference("family/states/$memberId")
        pending = store.read()?.let { JSONObject(it) }?.takeIf { it.optString("uid") == uid && it.optString("memberId") == memberId }
        authObserver = FirebaseAuth.AuthStateListener { auth -> if (auth.currentUser?.uid != uid) halt("Device authentication changed.") }
        FirebaseAuth.getInstance().addAuthStateListener(authObserver!!)
        observe(db.getReference("family/members/$memberId")) { snapshot ->
            if (snapshot.child("authUid").value != uid || snapshot.child("active").value != true) halt("This device needs approval again.")
        }
        observe(state.child("control")) { snapshot ->
            val nextRevision = (snapshot.child("revision").value as? Number)?.toLong() ?: -1L
            sharing = snapshot.child("sharingEnabled").value == true
            overridden = snapshot.child("overrideActive").value != false
            if (revision != nextRevision) {
                revision = nextRevision
                if (pending?.optLong("revision") != revision) { pending = null; store.clear() }
            }
            if (!sharing || overridden) { pending = null; store.clear(); halt("") }
            else { requestUpdates(); flush() }
        }
        observe(db.getReference(".info/connected")) { snapshot ->
            connected = snapshot.value == true
            if (connected) { retrySeconds = 5; flush() }
        }
        return START_STICKY
    }

    private fun observe(reference: DatabaseReference, change: (DataSnapshot) -> Unit) {
        val listener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) { if (!destroyed) change(snapshot) }
            override fun onCancelled(error: DatabaseError) { if (!destroyed) halt("Location service unavailable or device access revoked.") }
        }
        observers.add(reference to listener)
        reference.addValueEventListener(listener)
    }

    @Suppress("MissingPermission")
    private fun requestUpdates() {
        if (destroyed || !sharing || overridden) return
        client.removeLocationUpdates(callback)
        val interval = if (moving) 60000L else 300000L
        // A distance requirement blocks time-based updates on a stationary
        // phone. Keep it while moving; idle fixes still carry real timestamps.
        val minimumDistance = if (moving) 50f else 0f
        val request = LocationRequest.Builder(if (moving) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY, interval)
            .setMinUpdateIntervalMillis(interval).setMinUpdateDistanceMeters(minimumDistance).setMaxUpdateDelayMillis(interval).build()
        try {
            client.requestLocationUpdates(request, callback, Looper.getMainLooper()).addOnFailureListener { halt("Location permission or GPS is unavailable.") }
            if (lastMotion == 0L) { lastMotion = System.currentTimeMillis(); handler.postDelayed(idle, 180000) }
        } catch (_: SecurityException) { halt("Allow location access to resume sharing.") }
    }

    private fun flush() {
        if (destroyed) return
        val fix = pending ?: return
        if (!connected || uploading || !sharing || overridden || revision < 0) return
        if (fix.optLong("revision") != revision || fix.optString("uid") != uid) { pending = null; store.clear(); return }
        uploading = true
        state.runTransaction(object : Transaction.Handler {
            override fun doTransaction(data: MutableData): Transaction.Result {
                if (destroyed) return Transaction.abort()
                if (data.value == null) return Transaction.success(data)
                val control = data.child("control")
                if (control.child("sharingEnabled").value != true || control.child("overrideActive").value != false ||
                    (control.child("revision").value as? Number)?.toLong() != fix.optLong("revision")) return Transaction.abort()
                val previous = (data.child("location/measuredAt").value as? Number)?.toLong() ?: 0L
                if (fix.optLong("measuredAt") <= previous) return Transaction.abort()
                data.child("location").value = mapOf("latitude" to fix.getDouble("latitude"), "longitude" to fix.getDouble("longitude"),
                    "accuracy" to fix.getDouble("accuracy"), "measuredAt" to fix.getLong("measuredAt"), "publishedAt" to ServerValue.TIMESTAMP)
                return Transaction.success(data)
            }
            override fun onComplete(error: DatabaseError?, committed: Boolean, snapshot: DataSnapshot?) {
                if (destroyed) return
                uploading = false
                if (error?.code == DatabaseError.PERMISSION_DENIED) { halt("Location upload denied. Check device approval and phone time."); return }
                if (error == null) {
                    if (pending?.optLong("measuredAt") == fix.optLong("measuredAt")) { pending = null; store.clear() }
                    prefs.edit().putString("lastError", "").apply()
                    retrySeconds = 5
                    flush()
                } else {
                    prefs.edit().putString("lastError", "Location upload unavailable; retaining the latest fix.").apply()
                    handler.removeCallbacks(retry)
                    handler.postDelayed(retry, retrySeconds * 1000)
                    retrySeconds = min(300L, retrySeconds * 2)
                }
            }
        }, false)
    }

    private fun halt(message: String) {
        prefs.edit().putString("lastError", message).putBoolean("wanted", false).apply()
        pending = null
        store.clear()
        stopSelf()
    }

    override fun onDestroy() {
        destroyed = true
        stopForeground(STOP_FOREGROUND_REMOVE)
        client.removeLocationUpdates(callback)
        handler.removeCallbacksAndMessages(null)
        observers.forEach { (ref, listener) -> ref.removeEventListener(listener) }
        authObserver?.let { FirebaseAuth.getInstance().removeAuthStateListener(it) }
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
