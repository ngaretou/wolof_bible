import 'dart:async';

// import 'package:universal_html/html.dart' as html;
import 'package:flutter/services.dart';

import 'package:path_provider/path_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';

import 'package:url_strategy/url_strategy.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:pwa_install/pwa_install.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';
import 'package:macos_window_utils/macos_window_utils.dart' as macos;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:wolof_bible/logic/aquifer_api.dart';
import 'package:wolof_bible/widgets/whats_new.dart';
import 'firebase_options.dart';

import 'screens/about.dart';
import 'screens/bible_view.dart';
import 'screens/settings.dart';

import 'widgets/onboarding_panel.dart';

import 'theme.dart';
import 'macos_window_delegate.dart';
import 'logic/data_initializer.dart';

import 'providers/user_prefs.dart';
import 'providers/column_manager.dart';

import '../hive/user_columns_db.dart';

const appTitle = 'Kàddug Yàlla+';

/// Checks if the current environment is a desktop environment.
bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

late Box<UserColumnsDB> userColumnsBox;
late Box userPrefsBox;

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Keep native splash screen up until app is finished bootstrapping
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  PWAInstall().setup(
    //   installCallback: () {
    //   debugPrint('APP INSTALLED!');
    // }
  );

  // Hive stores its files in ApplicationDocumentsDirectory - for most platforms this works great, but Windows it stores these three files in the Documents directory. Yuck.
  // We've changed that now wtih await Hive.initFlutter('KaddugYalla'); but clean it up if a user has that old version.

  if (!kIsWeb && Platform.isWindows) {
    List<String> filesToMove = [
      'parsedlinedb.hive',
      'parsedlinedb.lock',
      'usercolumnsdb.hive',
      'usercolumnsdb.lock',
      'userprefs.hive',
      'userprefs.lock',
    ];

    String dir = (await getApplicationDocumentsDirectory()).path;

    for (var file in filesToMove) {
      String oldPath = '$dir/$file';
      String newPath = '$dir/KaddugYalla/$file';
      try {
        bool fileExists = await File(oldPath).exists();
        if (fileExists) {
          bool fileExistsInSubfolder = await File(newPath).exists();
          if (!fileExistsInSubfolder) {
            File(oldPath).copy(newPath).then((_) => File(oldPath).delete());
          } else {
            File(oldPath).delete();
          }
        }
      } catch (e) {
        debugPrint('Error moving hive files into documents directory');
        debugPrint(e.toString());
      }
    }
  }

  await Hive.initFlutter('KaddugYalla');
  Hive.registerAdapter(UserColumnsDBAdapter());

  userColumnsBox = await Hive.openBox<UserColumnsDB>('userColumnsDB');

  userPrefsBox = await Hive.openBox('userPrefs');

  // if it's not on the web, windows or android, load the accent color
  if (!kIsWeb &&
      [
        TargetPlatform.windows,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform)) {
    SystemTheme.accentColor.load();
  }

  setPathUrlStrategy();

  // No firebase for Windows yet so don't initialize it in that case, but do in other cases
  if (kIsWeb || !Platform.isWindows) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAnalytics analytics = FirebaseAnalytics.instance;
    await analytics.logAppOpen();
  }

  if (isDesktop) {
    // all desktop common settings
    await WindowManager.instance.ensureInitialized();

    windowManager.waitUntilReadyToShow().then((_) async {
      double? windowWidth = userPrefsBox.get('windowWidth');
      double? windowHeight = userPrefsBox.get('windowHeight');
      if (windowHeight == null || windowWidth == null) {
        windowWidth = 1000;
        windowHeight = 650;
      }

      await windowManager.setSize(Size(windowWidth, windowHeight));
      await windowManager.setMinimumSize(const Size(600, 650));
      await windowManager.center();
      await windowManager.show();
      await windowManager.setPreventClose(false);
      await windowManager.setSkipTaskbar(false);
    });

    // Windows and macos different settings
    if (Platform.isWindows) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        // windowButtonVisibility: true,
      );
      // await flutter_acrylic.Window.initialize();
    } else if (Platform.isMacOS) {
      // initialization of macos_window_utils
      WidgetsFlutterBinding.ensureInitialized();
      await macos.WindowManipulator.initialize(enableWindowDelegate: true);
      macos.WindowManipulator.hideTitle();
      macos.WindowManipulator.makeTitlebarTransparent();
      macos.WindowManipulator.enableFullSizeContentView();
      final delegate = MyDelegate();
      macos.WindowManipulator.addNSWindowDelegate(delegate);

      // Create macos.macos.NSAppPresentationOptions instance.
      final options = macos.NSAppPresentationOptions.from({
        // fullScreen needs to be present as a fullscreen presentation option at all
        // times.
        macos.NSAppPresentationOption.fullScreen,

        // Hide the toolbar automatically in fullscreen mode.
        macos.NSAppPresentationOption.autoHideToolbar,

        // autoHideToolbar must be accompanied by autoHideMenuBar.
        macos.NSAppPresentationOption.autoHideMenuBar,

        // autoHideMenuBar must be accompanied by either autoHideDock or hideDock.
        macos.NSAppPresentationOption.autoHideDock,
      });

      // Apply the options as fullscreen presentation options.
      options.applyAsFullScreenPresentationOptions();
    }
  }
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  // print('runApp');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (ctx) => UserPrefs()),
        ChangeNotifierProvider(create: (ctx) => ScrollGroup()),
        //This seems a bit hacky but there are two buttons in the navpane that are hard to reference so this provider helps there
        ChangeNotifierProvider(create: (ctx) => ColumnManager()),
        // only macos
      ],
      child: const MyApp(),
    ),
  );
}

final _appTheme = AppTheme();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // print('myapp build');
    ScrollbarThemeData scrollBarTheme = const ScrollbarThemeData(
      thickness: 6.0,
      hoveringThickness: 6.0,
      // backgroundColor: Color.fromARGB(204, 126, 126, 126),
      // scrollbarColor: Color.fromARGB(204, 37, 31, 125),
      // scrollbarPressingColor: Color.fromARGB(204, 18, 98, 54),
      // radius: const Radius.circular(100.0),
      // hoveringRadius: const Radius.circular(100.0),
      mainAxisMargin: 4.0,
      hoveringMainAxisMargin: 4.0,
      crossAxisMargin: 2.0,
      hoveringCrossAxisMargin: 2.0,
      minThumbLength: 48.0,
      // trackBorderColor: Color.fromARGB(85, 126, 126, 126),
      // hoveringTrackBorderColor: Color.fromARGB(85, 126, 126, 126),
      padding: EdgeInsets.all(0),
      hoveringPadding: EdgeInsets.all(0),
    );

    // print('initAppInfo');
    return ChangeNotifierProvider.value(
      value: _appTheme,
      builder: (context, _) {
        final appTheme = context.watch<AppTheme>();

        late SystemUiOverlayStyle style;
        if (appTheme.mode == ThemeMode.dark) {
          style = SystemUiOverlayStyle.light;
        } else {
          style = SystemUiOverlayStyle.dark;
        }

        SystemChrome.setSystemUIOverlayStyle(style);
        // print('about to hit Future Builder');
        return FluentApp(
          title: appTitle,
          themeMode: appTheme.mode,
          debugShowCheckedModeBanner: false,
          home: MyHomePage(appTheme: appTheme),
          color: appTheme.color,
          // color: Colors.black,
          darkTheme: FluentThemeData(
            brightness: Brightness.dark,
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            // focusTheme: FocusThemeData(
            //   glowFactor: is10footScreen() ? 2.0 : 0.0,
            // ),
            scrollbarTheme: scrollBarTheme,
            selectionColor: appTheme.color.darkest,
          ),
          theme: FluentThemeData(
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            // focusTheme: FocusThemeData(
            //   glowFactor: is10footScreen() ? 2.0 : 0.0,
            // ),
            scrollbarTheme: scrollBarTheme,
            selectionColor: appTheme.color.lightest,
          ),
          builder: (context, child) {
            return Directionality(
              textDirection: appTheme.textDirection,
              child: NavigationPaneTheme(
                data: NavigationPaneThemeData(
                  backgroundColor:
                      appTheme.windowEffect !=
                          flutter_acrylic.WindowEffect.disabled
                      ? Colors.transparent
                      : null,
                ),
                child: child!,
              ),
            );
          },
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  final AppTheme appTheme;

  const MyHomePage({super.key, required this.appTheme});

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> with WindowListener {
  int index = 0;

  final settingsController = ScrollController();

  final GlobalKey<NavigationViewState> viewKey =
      GlobalKey<NavigationViewState>();

  // Size windowSize = const Size(500, 500);
  // late bool isFullScreen;
  ValueNotifier<double> myProgress = ValueNotifier(0);

  void updateProgress(double progress) {
    // // print(progress);

    myProgress.value = progress;
  }

  Future<void> callInititalization() async {
    UserPrefs userPrefs = Provider.of<UserPrefs>(context, listen: false);
    if (collections.isEmpty) {
      collections = await collectionsFromXML(context, updateProgress);
    }

    await userPrefs.loadUserPrefs(collections);

    return;
  }

  Future<void> callInterfaceInitialization() async {
    await asyncGetTranslations(context);
    // for resource data in resource column
    // for resource data in resource column
    await AquiferService().initializeResourceData();
  }

  late Future<void> initCollections = callInititalization();
  late Future<void> initInterface;

  @override
  void initState() {
    initInterface = callInterfaceInitialization();
    // print('MyHomePageState initState');
    windowManager.addListener(this);

    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    settingsController.dispose();
    super.dispose();
  }

  // this works for Windows but for macos we've got the macos_window_delegate.dart file
  Future<void> saveWindowSize() async {
    Size media = await windowManager.getSize();
    userPrefsBox.put('windowHeight', media.height);
    userPrefsBox.put('windowWidth', media.width);
  }

  @override
  void onWindowResize() {
    if (isDesktop) {
      saveWindowSize();
    }
    super.onWindowResize();
  }

  @override
  void onWindowResized() {
    if (isDesktop) {
      saveWindowSize();
    }
    super.onWindowResized();
  }

  //This works as far as it goes - the problem is that it can't detect when we are already in full screen.
  // void goFullScreen() {
  //   html.document.documentElement?.requestFullscreen();
  // }

  // void exitFullScreen() {
  //   html.document.exitFullscreen();
  // }

  // void toggleFullScreen() {
  //   if (isFullScreen) {
  //     html.document.exitFullscreen();
  //   } else {
  //     html.document.documentElement?.requestFullscreen();
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    // print('MyHomePageState build');

    bool hasSeenOnboarding = userPrefsBox.get(
      'hasSeenOnboarding',
      defaultValue: false,
    );

    if (hasSeenOnboarding == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          barrierDismissible: true,
          context: context,
          builder: (BuildContext context) {
            return const Center(child: OnboardingPanel());
          },
        ).then((_) {
          setState(() {});
        });

        //save that the user has seen the onboarding
        userPrefsBox.put('hasSeenOnboarding', true);
      });
    }

    return FutureBuilder(
      future: initInterface,
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: ProgressRing());
        } else {
          final translation = Provider.of<UserPrefs>(
            context,
            listen: true,
          ).currentTranslation;
          List<NavigationPaneItem> finalNavPaneItems = [];

          //For Wolof only and on web only on kaddugyalla.com
          List<NavigationPaneItem> wolofWebOnlyNavPaneItems = [
            if (kIsWeb)
              PaneItemAction(
                icon: const Icon(FluentIcons.download),
                title: Text(translation.downloadApp),
                onTap: () {
                  showDialog(
                    barrierDismissible: true,
                    context: context,
                    builder: (BuildContext context) {
                      return const Center(
                        child: OnboardingPanel(appDownloadOnly: true),
                      );
                    },
                  );
                },
              ),
            // go to kaddugyalla.com
            PaneItemAction(
              icon: const Icon(FluentIcons.open_in_new_window),
              title: const Text('kaddugyalla.com'),
              onTap: () {
                openUrl('https://kaddugyalla.com');
              },
            ),
            //More apps
            PaneItemAction(
              icon: const Icon(FluentIcons.app_icon_default),
              title: Text(translation.moreApps),
              onTap: () {
                openUrl('https://sng.al/app');
              },
            ),
            //Contact
            PaneItemAction(
              icon: const Icon(FluentIcons.mail),
              title: const Text('Bind nu'),
              onTap: () {
                openUrl(
                  'http://currah.download/pages/wolof/bible/contact/index.html',
                );
              },
            ),
          ];

          //Normal pane items we always use
          List<NavigationPaneItem> normalNavPaneItems = [
            PaneItemSeparator(),

            //Light Dark Toggle
            PaneItemAction(
              icon: FluentTheme.of(context).brightness == Brightness.dark
                  ? const Icon(FluentIcons.sunny)
                  : const Icon(FluentIcons.clear_night),
              title: FluentTheme.of(context).brightness == Brightness.dark
                  ? Text(translation.lightTheme)
                  : Text(translation.darkTheme),
              onTap: () {
                Future<void> saveThemeMode(String themeMode) async {
                  Box userPrefsBox = await Hive.openBox('userPrefs');
                  userPrefsBox.put('themeMode', themeMode);
                  // userPrefsBox.close();
                }

                /*Couple of cases here - by default it's set to user theme mode, but we want 
                to offer a way to change that easily. So account for whether the system theme
                mode is dark or light, and switch to an expressly declared light or dark*/
                switch (widget.appTheme.mode) {
                  case ThemeMode.system:
                    bool dark =
                        (MediaQuery.of(context).platformBrightness ==
                        Brightness.dark);
                    if (dark) {
                      widget.appTheme.mode = ThemeMode.light;
                    } else {
                      widget.appTheme.mode = ThemeMode.dark;
                    }
                    break;
                  case ThemeMode.dark:
                    widget.appTheme.mode = ThemeMode.light;
                    break;
                  case ThemeMode.light:
                    widget.appTheme.mode = ThemeMode.dark;
                    break;
                }
                saveThemeMode(widget.appTheme.mode.toString());
              },
            ),

            //About
            PaneItem(
              body: const About(),
              icon: const Icon(FluentIcons.info),
              title: Text(translation.about),
            ),
            PaneItem(
              body: Settings(controller: settingsController),
              icon: const Icon(FluentIcons.settings),
              title: Text(translation.settings),
            ),
          ];

          //Set up the navPaneItems - note that if the name of the wolof app gets changed by one char it will not work

          finalNavPaneItems.addAll(wolofWebOnlyNavPaneItems);
          finalNavPaneItems.addAll(normalNavPaneItems);

          Widget? titleBar({double height = 28}) {
            if (kIsWeb) {
              return SizedBox(height: 4);
            } else if (Platform.isWindows) {
              return TitleBar(
                title: () {
                  if (kIsWeb) return Text(appTitle);
                  return DragToMoveArea(
                    child: Row(
                      children: [
                        const SizedBox(width: 15),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(appTitle),
                        ),
                      ],
                    ),
                  );
                }(),

                endHeader: const Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    //     IconButton(
                    //         icon: const Icon(FluentIcons.add),
                    //         onPressed: () {
                    //           numberOfColumns <= 3 //keep it to four columns
                    //               ? changeNumberColumns(add: true)
                    //               : null;

                    //           // setState(() {});
                    //         }),

                    //     // Spacer(),
                    WindowButtons(),
                  ],
                ),
              );
            } else if (Platform.isMacOS) {
              return SizedBox(
                height: height,
                child: height == 4
                    ? null
                    : DragToMoveArea(child: Center(child: Text(appTitle))),
              );
            } else if (Platform.isIOS) {
              return SizedBox(height: 22);
            } else {
              return SizedBox(height: 4);
            }
          }

          Widget appBody() {
            return FutureBuilder(
              future: initCollections,
              builder: (ctx, snapshot) {
                // Remove splash screen when bootstrap is complete
                FlutterNativeSplash.remove();

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ValueListenableBuilder<double>(
                    valueListenable: myProgress,
                    builder: (context, val, child) {
                      if (val == 0) {
                        return const Center(child: ProgressRing());
                      } else {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                ProgressRing(value: val),
                                if (val.ceil() != 100)
                                  Text(
                                    '${val.ceil().toString()}%',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                              ],
                            ),
                            SizedBox(
                              height:
                                  (MediaQuery.of(context).size.height / 2) - 70,
                            ),

                            const SizedBox(height: 30),
                          ],
                        );
                      }
                    },
                  );
                }
                //Main row that holds the text columns
                else {
                  //Sets a default in case there is no RTL below
                  late String comboBoxFont =
                      collections.first.fonts.first.fontFamily;
                  bool anyRTL = collections.any(
                    (element) => element.textDirection != 'LTR',
                  );

                  if (anyRTL) {
                    String font = collections
                        .firstWhere((element) => element.textDirection == 'RTL')
                        .fonts
                        .first
                        .fontFamily;
                    comboBoxFont = font;
                  }

                  return BibleView(
                    collections: collections,
                    comboBoxFont: comboBoxFont,
                  );
                }
              },
            );
          }

          return ValueListenableBuilder<Box?>(
            valueListenable: userPrefsBox.listenable(keys: ['fullscreen']),
            builder: (context, _, child) {
              double height = 28;
              bool? fullscreen = userPrefsBox.get('fullscreen');
              if (fullscreen != null) {
                if (fullscreen) {
                  height = 4;
                } else {
                  height = 28;
                }
              }

              ValueNotifier<bool> isPaneOpen = ValueNotifier(false);

              if (viewKey.currentState?.compactOverlayOpen == true) {
                isPaneOpen.value = true;
              }

              return NavigationView(
                key: viewKey,

                //appBar is across top of the screen in place of normal OS specific title bar.
                titleBar: titleBar(height: height),
                // titleBar: null,
                //Main big row that holds the text columns
                pane: NavigationPane(
                  selected: index,
                  toggleButton: Icon(FluentIcons.collapse_menu),
                  onChanged: (i) => setState(() => index = i),
                  header: SizedBox.shrink(),
                  // header: const Text('Pane Header'),
                  displayMode: PaneDisplayMode.compact,

                  indicator: const StickyNavigationIndicator(),
                  items: [
                    PaneItemAction(
                      icon: ValueListenableBuilder(
                        valueListenable: isPaneOpen,
                        builder: (context, val, _) {
                          return SizedBox(
                            // this 47 is for some reason important for fluent_ui - they have some bouncing placement when menu is toggled open
                            // spent quite a while getting this right and it's stll not 100%
                            height: val == true ? 14 : 47,
                            child: val == true
                                ? Icon(FluentIcons.back)
                                : Icon(FluentIcons.collapse_menu),
                          );
                        },
                      ),

                      onTap: () {
                        viewKey.currentState?.toggleCompactOpenMode();
                        isPaneOpen.value = !isPaneOpen.value;
                      },
                    ),

                    // Open Main Bible View
                    PaneItem(
                      body: child!,
                      icon: const Icon(FluentIcons.reading_mode_solid),
                      title: Text(appTitle),
                    ),

                    //Search
                    PaneItemAction(
                      title: Text(translation.search),
                      icon: const Icon(FluentIcons.search),
                      onTap: () {
                        if (index != 0) {
                          setState(() {
                            index = 0;
                          });
                        }
                        Provider.of<ColumnManager>(
                          context,
                          listen: false,
                        ).toggleSearch();
                      },
                    ),
                    //Add Column
                    PaneItemAction(
                      icon: const Icon(FluentIcons.calculator_addition),
                      title: Text(translation.addColumn),

                      onTap: () {
                        if (index != 0) {
                          setState(() {
                            index = 0;
                          });
                        }
                        Provider.of<UserPrefs>(
                          context,
                          listen: false,
                        ).addColumn(context, ColumnType.scripture);
                      },
                    ),
                    //Open Resource Column
                    PaneItemAction(
                      icon: WhatsNew(
                        icon: const Icon(FluentIcons.diet_plan_notebook),
                        title: translation.newStudyNotes,
                        subtitle: translation.newStudyNotesSub,
                        flag: 'hasSeenResourceIntro',
                        // wait til this is true before showing
                        gate: hasSeenOnboarding,
                        placementMode: .rightCenter,

                        child: const Icon(FluentIcons.diet_plan_notebook),
                      ),

                      title: Text(translation.openResourceColumn),

                      onTap: () {
                        if (index != 0) {
                          setState(() {
                            index = 0;
                          });
                        }
                        Provider.of<UserPrefs>(
                          context,
                          listen: false,
                        ).addColumn(context, ColumnType.resource);
                      },
                    ),
                  ],
                  footerItems: finalNavPaneItems,
                ),
              );
            },
            child: appBody(),
          );
        }
      },
    );
  }

  @override
  void onWindowClose() async {
    // print('closing');
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) {
          return ContentDialog(
            title: const Text('Confirm close'),
            content: const Text('Are you sure you want to close this window?'),
            actions: [
              FilledButton(
                child: const Text('Yes'),
                onPressed: () {
                  Navigator.pop(context);
                  windowManager.destroy();
                },
              ),
              Button(
                child: const Text('No'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    }
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);

    return SizedBox(
      width: 138,
      height: 50,
      child: WindowCaption(
        brightness: theme.brightness,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}

Future<void> openUrl(String url) async {
  if (await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url), webOnlyWindowName: "_blank");
  } else {
    throw 'Could not launch $url';
  }
}
