import 'package:macos_window_utils/macos/ns_window_delegate.dart';
import 'main.dart';

class MyDelegate extends NSWindowDelegate {
  @override
  void windowDidEnterFullScreen() {
    userPrefsBox.put('fullscreen', true);
    super.windowDidEnterFullScreen();
  }

  @override
  void windowDidExitFullScreen() {
    userPrefsBox.put('fullscreen', false);
    super.windowDidExitFullScreen();
  }
}

// Managing Full-Screen Presentation:
// windowWillEnterFullScreen
// windowDidEnterFullScreen
// windowWillExitFullScreen
// windowDidExitFullScreen
