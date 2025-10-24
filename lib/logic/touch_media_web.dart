import 'dart:js_interop';

@JS('window')
external _JSWindow get _window;

@JS()
@staticInterop
class _JSWindow {}

extension _JSWindowExt on _JSWindow {
  external _MediaQueryList matchMedia(String query);
}

@JS()
@staticInterop
class _MediaQueryList {}

extension _MediaQueryListExt on _MediaQueryList {
  external bool get matches;
}

/// Web implementation: window.matchMedia(query).matches
bool mediaMatches(String query) => _window.matchMedia(query).matches;