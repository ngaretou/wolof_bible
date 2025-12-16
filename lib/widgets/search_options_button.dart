import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../logic/data_initializer.dart';
import '../providers/user_prefs.dart';

class SearchOptionsButton extends StatefulWidget {
  final List<String> selectedCollections;
  final ValueChanged<List<String>> onCollectionsChanged;
  final bool fuzzy;
  final ValueChanged<bool> onFuzzyChanged;
  final String? font;

  const SearchOptionsButton({
    super.key,
    required this.selectedCollections,
    required this.onCollectionsChanged,
    required this.fuzzy,
    required this.onFuzzyChanged,
    this.font,
  });

  @override
  State<SearchOptionsButton> createState() => _SearchOptionsButtonState();
}

class _SearchOptionsButtonState extends State<SearchOptionsButton> {
  final FlyoutController _controller = FlyoutController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TextStyle style = DefaultTextStyle.of(
    //   context,
    // ).style.copyWith(fontFamily: widget.font, fontSize: 14);
    TextStyle style = DefaultTextStyle.of(context).style;

    return FlyoutTarget(
      controller: _controller,
      child: IconButton(
        icon: const Icon(FluentIcons.settings),
        onPressed: () {
          _controller.showFlyout(
            autoModeConfiguration: FlyoutAutoConfiguration(
              preferredMode: FlyoutPlacementMode.bottomCenter,
            ),
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            dismissWithEsc: true,
            builder: (context) {
              return StatefulBuilder(
                builder: (context, setState) {
                  return FlyoutContent(
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Collections Checkboxes
                          ...List.generate(collections.length, (i) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Checkbox(
                                checked: widget.selectedCollections.contains(
                                  collections[i].id,
                                ),
                                onChanged: (bool? value) {
                                  // Update local UI immediately via setState
                                  setState(() {
                                    final newCollections = List<String>.from(
                                      widget.selectedCollections,
                                    );
                                    if (newCollections.contains(
                                      collections[i].id,
                                    )) {
                                      newCollections.remove(collections[i].id);
                                    } else {
                                      newCollections.add(collections[i].id);
                                    }
                                    // Propagate change
                                    widget.onCollectionsChanged(newCollections);
                                  });
                                },
                                content: Text(
                                  collections[i].name,
                                  style: style,
                                ),
                              ),
                            );
                          }),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Divider(),
                          ),
                          // Fuzzy / Strict Radio Buttons
                          RadioButton(
                            checked: widget.fuzzy,
                            onChanged: (val) {
                              if (val) {
                                setState(() {
                                  widget.onFuzzyChanged(true);
                                });
                              }
                            },
                            content: Text(
                              Provider.of<UserPrefs>(
                                context,
                                listen: false,
                              ).currentTranslation.fuzzySearch,
                              style: style,
                            ),
                          ),
                          const SizedBox(height: 8),
                          RadioButton(
                            checked: !widget.fuzzy,
                            onChanged: (val) {
                              if (val) {
                                setState(() {
                                  widget.onFuzzyChanged(false);
                                });
                              }
                            },
                            content: Text(
                              Provider.of<UserPrefs>(
                                context,
                                listen: false,
                              ).currentTranslation.strictSearch,
                              style: style,
                            ),
                          ),
                        ],
                      ),
                    ),
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
