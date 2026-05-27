package com.example.tracklog

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "TrackLog_Maps"
        private const val CHANNEL = "com.example.tracklog/diagnostics"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Log the actual API key value baked into BuildConfig at compile time
        val mapsKey = BuildConfig.GOOGLE_MAPS_API_KEY
        Log.d(TAG, "=== MAPS DIAGNOSTIC ===")
        Log.d(TAG, "GOOGLE_MAPS_API_KEY length: ${mapsKey.length}")
        Log.d(TAG, "GOOGLE_MAPS_API_KEY empty: ${mapsKey.isEmpty()}")
        Log.d(TAG, "GOOGLE_MAPS_API_KEY prefix: ${if (mapsKey.length > 6) mapsKey.substring(0, 6) + "..." else "(too short)"}")
        Log.d(TAG, "======================")

        // Also log the string resource value used by the manifest
        try {
            val resId = resources.getIdentifier("google_maps_key", "string", packageName)
            if (resId != 0) {
                val resValue = getString(resId)
                Log.d(TAG, "String resource google_maps_key length: ${resValue.length}")
                Log.d(TAG, "String resource google_maps_key prefix: ${if (resValue.length > 6) resValue.substring(0, 6) + "..." else "(too short)"}")
            } else {
                Log.e(TAG, "String resource google_maps_key NOT FOUND in resources!")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading string resource: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Expose BuildConfig values to Flutter via platform channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMapsKeyStatus" -> {
                        val key = BuildConfig.GOOGLE_MAPS_API_KEY
                        result.success(mapOf(
                            "keyLength" to key.length,
                            "isEmpty" to key.isEmpty(),
                            "prefix" to if (key.length > 6) key.substring(0, 6) else key,
                            "isValid" to (key.length > 20)
                        ))
                    }
                    "getMapsApiKey" -> {
                        // Return full key for direct initialization fallback
                        result.success(BuildConfig.GOOGLE_MAPS_API_KEY)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
