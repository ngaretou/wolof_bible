import 'package:fluent_ui/fluent_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:wolof_bible/widgets/resource_column.dart';
import '../logic/aquifer_api.dart';
import '../main.dart';
import '../providers/aquifer_classes.dart';

class ResourceChooser extends StatefulWidget {
  final void Function(String) onChanged;
  final void Function() onShouldUpdateContent;
  final List<String> resourceCodes;
  final int langId;
  final TextDirection textDirection;
  const ResourceChooser({
    super.key,
    required this.onChanged,
    required this.onShouldUpdateContent,
    required this.resourceCodes,
    required this.langId,
    required this.textDirection,
  });

  @override
  State<ResourceChooser> createState() => _ResourceChooserState();
}

class _ResourceChooserState extends State<ResourceChooser> {
  bool shouldUpdateContent = false;

  @override
  Widget build(BuildContext context) {
    final itemsController = FlyoutController();
    List<ResourceCollectionInfo> resourceCollections = AquiferService()
        .getResourcesForLanguage(widget.langId);

    itemsController.addListener(() {
      if (!itemsController.isOpen) {
        if (shouldUpdateContent) {
          widget.onShouldUpdateContent();
          shouldUpdateContent = false;
        }
      }
    });

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
              return Directionality(
                textDirection: widget.textDirection,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return FlyoutContent(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: resourceCollections.map((collection) {
                          return Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: ToggleSwitch(
                              checked: widget.resourceCodes.contains(
                                collection.code,
                              ),
                              onChanged: (v) {
                                // if there's a change, make it so the content is updated
                                shouldUpdateContent = true;
                                setState(() {
                                  widget.onChanged(collection.code);
                                });
                              },
                              content: SizedBox(
                                width: 250,
                                child: Row(
                                  children: [
                                    Icon(contentIcon(collection.code)),
                                    SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        collection.availableLanguages
                                            .where((l) => l.id == widget.langId)
                                            .first
                                            .displayName,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              );
              // return StatefulBuilder(
              //   builder: (context, setStateChild) {
              //     return MenuFlyout(
              //       items: resourceCollections.map((collection) {
              //         return ToggleMenuFlyoutItem(
              //           text: Text(
              //             collection.availableLanguages
              //                 .where((l) => l.id == widget.langId)
              //                 .first
              //                 .displayName,
              //           ),
              //           value: resourceCodes.contains(collection.code),
              //           onChanged: (v) {
              //             setState(() {
              //               if (v) {
              //                 resourceCodes.add(collection.code);
              //               } else {
              //                 resourceCodes.remove(collection.code);
              //               }
              //             });
              //             widget.onChanged(collection.code);
              //           },
              //         );
              //       }).toList(),
              //     );
              //   },
              // );
            },
          );
        },
      ),
    );
  }
}
