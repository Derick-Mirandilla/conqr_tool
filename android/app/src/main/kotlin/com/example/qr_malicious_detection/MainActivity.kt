package com.example.qr_malicious_detection

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode

class MainActivity: FlutterActivity() {
    private val CHANNEL = "google_code_scanner"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "scanCode") {
                val options = GmsBarcodeScannerOptions.Builder()
                    .setBarcodeFormats(Barcode.FORMAT_QR_CODE) // Only scan QR codes
                    .build()

                val scanner = GmsBarcodeScanning.getClient(this, options)

                scanner.startScan()
                    .addOnSuccessListener { barcode ->
                        result.success(barcode.rawValue) // Return scanned string
                    }
                    .addOnCanceledListener {
                        result.success(null)
                    }
                    .addOnFailureListener { e ->
                        result.error("SCAN_FAILED", e.localizedMessage, null)
                    }
            } else {
                result.notImplemented()
            }
        }
    }
}
