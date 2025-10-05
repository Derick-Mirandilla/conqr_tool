import 'package:flutter/services.dart';

class GoogleCodeScanner {
  static const MethodChannel _channel = MethodChannel('google_code_scanner');

  /// Opens the Google Code Scanner and returns the scanned QR string (or null if canceled).
  static Future<String?> scanCode() async {
    final result = await _channel.invokeMethod<String>('scanCode');
    return result;
  }
}
