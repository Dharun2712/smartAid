import 'package:flutter/foundation.dart';

/// Lightweight logger to reduce print spam in debug and noop in release.
class Log {
  /// Enable or disable debug logs at runtime (effective only in debug/profile).
  static bool enableDebug = true;

  static void d(String message) {
    if (kReleaseMode) return; // No logs in release
    if (!enableDebug) return;
    debugPrint(message);
  }

  static void i(String message) {
    if (kReleaseMode) return;
    debugPrint('[INFO] $message');
  }

  static void w(String message) {
    if (kReleaseMode) return;
    debugPrint('[WARN] $message');
  }

  static void e(Object error, [StackTrace? stack]) {
    if (kReleaseMode) return;
    debugPrint('[ERROR] $error');
    if (stack != null) {
      debugPrint(stack.toString());
    }
  }
}
