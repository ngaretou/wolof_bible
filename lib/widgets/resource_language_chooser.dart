import 'package:fluent_ui/fluent_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../logic/aquifer_api.dart';
import '../main.dart';
import '../providers/aquifer_classes.dart';

class ResourceLanguageChooser extends StatefulWidget {
  final bool connected;
  final void Function(int) onChanged;
  final int incomingUserResourceLanguageCode;
  const ResourceLanguageChooser({
    super.key,
    required this.connected,
    required this.onChanged,
    required this.incomingUserResourceLanguageCode,
  });

  @override
  State<ResourceLanguageChooser> createState() =>
      _ResourceLanguageChooserState();
}

class _ResourceLanguageChooserState extends State<ResourceLanguageChooser> {
  List<ResourceLanguage> languages = [];
  int userResourceLanguageCode = 1;


  @override
  void initState() {
    super.initState();
    userResourceLanguageCode = widget.incomingUserResourceLanguageCode;
  }

  @override
  Widget build(BuildContext context) {
    final itemsController = FlyoutController();

    return FlyoutTarget(
      controller: itemsController,
      child: IconButton(
        icon: const Icon(FluentIcons.settings),
        onPressed: () {
          itemsController.showFlyout(
            autoModeConfiguration: FlyoutAutoConfiguration(
              preferredMode: FlyoutPlacementMode.topCenter,
            ),
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            dismissWithEsc: true,
            // navigatorKey: rootNavigatorKey.currentState,
            builder: (context) {
              return StatefulBuilder(
                builder: (context, setStateChild) {
                  return MenuFlyout(
                    items: languages.map((language) {
                      return RadioMenuFlyoutItem<int>(
                        text: Text(language.localizedDisplay),
                        value: language.id,
                        groupValue: userResourceLanguageCode,
                        onChanged: (v) {
                          // use it here
                          userResourceLanguageCode = v;
                          // store it
                          userPrefsBox.put('userResourceLanguageCode', v);
                          // notify parent
                          widget.onChanged(v);
                        },
                      );
                    }).toList(),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
