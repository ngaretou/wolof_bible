import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class UserInterAction extends StatelessWidget {
  const UserInterAction({
    required this.child,
    required this.partOfScrollGroup,
    required this.setActiveColumnKey,
    super.key,
  });

  final Widget child;
  final bool partOfScrollGroup;
  final Function setActiveColumnKey;

  @override
  Widget build(BuildContext context) {
    void setMeAsLeader() {
      if (partOfScrollGroup) {
        setActiveColumnKey();
      }
    }

    if (kIsWeb || Platform.isWindows) {
      return Listener(
        onPointerDown: (details) {
          setMeAsLeader();
        },
        onPointerSignal: (event) {
          setMeAsLeader();
        },
        child: child,
      );
    } else {
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            setMeAsLeader();
          }
          return true; // Allow notification to continue bubbling up
        },
        child: child,
      );
    }
  }
}
