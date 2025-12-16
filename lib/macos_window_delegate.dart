import 'dart:ui';
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

  @override
  void windowWillResize({required Size to}) {
    userPrefsBox.put('windowWidth', to.width);
    userPrefsBox.put('windowHeight', to.height);
    super.windowWillResize(to: to);
  }
}

// Managing Full-Screen Presentation:
// windowWillEnterFullScreen
// windowDidEnterFullScreen
// windowWillExitFullScreen
// windowDidExitFullScreen
