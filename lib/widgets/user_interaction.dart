import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class UserInterAction extends StatelessWidget {
  const UserInterAction(
      {required this.child,
      required this.partOfScrollGroup,
      required this.setActiveColumnKey,
      super.key});

  final Widget child;
  final bool partOfScrollGroup;
  final Function setActiveColumnKey;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Listener(
          onPointerDown: (details) {
            // on touch screen and scrollbar

            if (partOfScrollGroup) {
              // print(
              //     'setting myself as active key in column ${widget.myColumnIndex}| ${details.toString()}');
              setActiveColumnKey();
            }
          },
          onPointerSignal: (event) {
            // two finger scroll macos
            if (partOfScrollGroup) {
              // print(
              //     'setting myself as active key in column ${widget.myColumnIndex}');
              setActiveColumnKey();
            }
          },
          child: child);
    } else {
      return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // print(notification);
            // When a user starts a drag/scroll gesture on this column,
            // designate it as the leader of the scroll group.

            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              if (partOfScrollGroup) {
                // print(
                //     'setting myself as active key in column ${widget.myColumnIndex}| $notification');
                setActiveColumnKey();
              }
            }
            return true; // Allow notification to continue bubbling up
          },
          child: child);
    }
  }
}
