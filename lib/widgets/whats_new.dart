import 'package:fluent_ui/fluent_ui.dart';
import '../main.dart';

class WhatsNew extends StatefulWidget {
  final Widget child;
  final String flag;
  final FlyoutPlacementMode placementMode;
  final bool gate;
  final Icon icon;
  final String title;
  final String subtitle;

  const WhatsNew({
    super.key,
    required this.child,
    required this.flag,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.placementMode,
    required this.gate,
  });

  @override
  State<WhatsNew> createState() => _WhatsNewState();
}

class _WhatsNewState extends State<WhatsNew> {
  final flyoutController = FlyoutController();

  void showResourceIntro() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showTeachingTip(
        flyoutController: flyoutController,
        placementMode: widget.placementMode,
        builder: (context) {
          // userPrefsBox.put('hasSeenResourceIntro', true);
          return TeachingTip(
            leading: widget.icon,
            title: Text(widget.title),
            subtitle: Text(widget.subtitle),
          );
        },
      );
    });
  }

  @override
  void initState() {
    // this is the check to see if the user has seen this intro
    bool hasSeen = userPrefsBox.get(widget.flag) ?? false;
    if (!hasSeen && widget.gate) {
      userPrefsBox.put(widget.flag, true);
      showResourceIntro();
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(controller: flyoutController, child: widget.child);
  }
}
