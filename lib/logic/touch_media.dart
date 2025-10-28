// import 'package:flutter/foundation.dart' show kIsWeb;

// Use the js_interop implementation only on web builds.
import 'touch_media_stub.dart' if (dart.library.html) 'touch_media_web.dart';

/// Returns true on Web if the **primary** pointer is coarse (touch-first).
bool isTouchWebDevice({bool Function(String query)? mediaMatcher}) {
  // if (!kIsWeb) return false;

  final matcher = mediaMatcher ?? mediaMatches;
  // return matcher('(pointer: coarse)');

  // For hybrid devices (treat any touch capability as "touch"):
  return matcher('(pointer: coarse)') || matcher('(any-pointer: coarse)');
}
