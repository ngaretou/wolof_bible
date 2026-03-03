import 'package:provider/provider.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolof_bible/screens/bulk_verse_copy.dart';
import '../logic/data_initializer.dart';
import 'package:xml/xml.dart';

import '../providers/user_prefs.dart';

import '../widgets/onboarding_panel.dart';

class About extends StatelessWidget {
  // const About({super.key});
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    const spacer = SizedBox(width: 20);
    final translation = Provider.of<UserPrefs>(
      context,
      listen: false,
    ).currentTranslation;
    // const isRunningWithWasm = bool.fromEnvironment('dart.tool.dart2wasm');

    // // print('about page build');
    // appDef info
    String appName = '';
    String versionName = '';
    String programType = '';
    String programVersion = '';

    AssetBundle assetBundle = DefaultAssetBundle.of(context);

    //Get collection copyright strings from the appdef
    Future<Map<String, String>> getCollectionCopyrights() async {
      Map<String, String> results = {};

      //get the appDef xml from outside the flutter project
      String appDefLocation = 'assets/json/appDef.appDef';
      String xmlFileString = await assetBundle.loadString(appDefLocation);
      //get the document into a usable iterable
      final document = XmlDocument.parse(xmlFileString);
      //This is the info for all collectionsp
      Iterable<XmlElement> xmlCollections = document
          .getElement('app-definition')!
          .findAllElements('books');

      for (XmlElement xmlCollection in xmlCollections) {
        String id = xmlCollection.getAttribute('id').toString();

        Iterable<XmlElement>? xmlMetadata = xmlCollection
            .getElement('metadata')
            ?.findAllElements('meta');

        if (xmlMetadata != null) {
          for (XmlElement xmlMeta in xmlMetadata) {
            if (xmlMeta.getAttribute('name') == 'copyright-text') {
              results.addAll({id: xmlMeta.getAttribute('content').toString()});
            }
          }
        }
      }

      return results;
    }

    Future<void> getVariables() async {
      //get the appDef xml from outside the flutter project
      String appDefLocation = 'assets/json/appDef.appDef';
      String xmlFileString = await assetBundle.loadString(appDefLocation);
      //get the document into a usable iterable
      final document = XmlDocument.parse(xmlFileString);

      appName = document
          .getElement('app-definition')!
          .getElement('app-name')!
          .innerText
          .toString(); // e.g. Kaddug Yalla
      versionName = document
          .getElement('app-definition')!
          .getElement('version')!
          .getAttribute('name')
          .toString(); // e.g. 1.0
      programType = document
          .getElement('app-definition')!
          .getAttribute('type')
          .toString(); // e.g. SAB
      programVersion = document
          .getElement('app-definition')!
          .getAttribute('program-version')
          .toString(); // e.g. 9.3
    }

    Future<String> getHtml() async {
      await getVariables();
      //First get the copyrights from the appdef
      Map<String, String> copyrights = await getCollectionCopyrights();

      //Get the main about page html

      String aboutPageHtml = await assetBundle.loadString(
        "assets/project/data/about/about.txt",
      );

      //Now for each of the copyright texts we have, check to see if the appbuilder wants that text in the about page
      for (var k in copyrights.keys) {
        //check to see if the corresponding variable is present: e.g. %copyright-all:C01%
        RegExpMatch? match = RegExp(
          '%copyright-all:$k%',
        ).firstMatch(aboutPageHtml);

        //If present, replace variable with copyright text
        if (match != null) {
          String composedCopyrightStatement =
              '<br><hr style="margin-top: 0px; margin-bottom: 10px;"><h2>${collections.where((element) => element.id == k).first.name}</h2><br>${copyrights[k]}<br>';

          aboutPageHtml = aboutPageHtml.replaceAll(
            RegExp('%copyright-all:$k%'),
            composedCopyrightStatement,
          );
        }
      }

      //Now all html is in
      //Clean up other variables
      aboutPageHtml = aboutPageHtml.replaceAll(RegExp(r'%app-name%'), appName);
      aboutPageHtml = aboutPageHtml.replaceAll(
        RegExp(r'%version-name%'),
        versionName,
      );
      aboutPageHtml = aboutPageHtml.replaceAll(
        RegExp(r'%program-type%'),
        programType,
      );
      aboutPageHtml = aboutPageHtml.replaceAll(
        RegExp(r'%program-version%'),
        programVersion,
      );

      //Replace any \n line breaks with html breaks
      aboutPageHtml = aboutPageHtml.replaceAll(RegExp(r'\\n'), '<br>');

      //Clean up any variables for collections that have them but there is no text for them
      aboutPageHtml = aboutPageHtml.replaceAll(
        RegExp('%copyright-all:C0\\d%'),
        '',
      );

      //       String styleBlock = '''<style>
      //   body h2 {
      //     margin-top: 0;
      //     color: blue;
      //   }
      // </style>
      // ''';
      // return styleBlock + aboutPageHtml;

      String appCopyright = '''
<br>
<hr style="margin-top: 0px; margin-bottom: 20px;">
Kàddug Yàlla+ app © 2026 Foundational LLC.
<br> 
''';
      return aboutPageHtml + appCopyright;
    }

    Future<String> htmlToRender = getHtml();

    Widget htmlToDisplay() {
      return FutureBuilder(
        future: htmlToRender,
        builder: (ctx, snapshot) =>
            snapshot.connectionState == ConnectionState.waiting
            ? const Center(child: ProgressRing())
            //this is actually where the business happens; HTML just takes the data and renders it
            //SelectableHtml makes it selectable but you lose some formatting
            : Html(
                data: snapshot.data.toString(),
                onLinkTap:
                    (
                      String? url,
                      Map<String, String> attributes,
                      element,
                    ) async {
                      if (url != null) {
                        await canLaunchUrl(Uri.parse(url))
                            ? await launchUrl(Uri.parse(url))
                            : throw 'Could not launch $url';
                      }
                    },
              ),
      );
    }

    late PackageInfo packageInfo;

    getPackageInfo() async {
      packageInfo = await PackageInfo.fromPlatform();
    }

    List<Widget> pageContent = [
      Column(
        mainAxisAlignment: .center,
        crossAxisAlignment: .center,
        children: [
          htmlToDisplay(),
          Divider(),
          SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 200,
                child: Button(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        final size = MediaQuery.of(context).size;

                        return ContentDialog(
                          constraints: BoxConstraints(
                            maxWidth: size.width,
                            maxHeight: size.height - 20,
                          ),
                          title: Text(translation.bulkVerseCopy),
                          content: const BulkVerseCopy(),
                          actions: [
                            Button(
                              child: Text(translation.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Text(translation.bulkVerseCopy),
                ),
              ),
              spacer,
              SizedBox(
                width: 200,
                child: Button(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return const Center(child: OnboardingPanel());
                      },
                    );
                  },
                  child: const Text('Intro'),
                ),
              ),
              spacer,
              SizedBox(
                width: 200,
                child: Button(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return ContentDialog(
                          constraints: BoxConstraints(
                            maxWidth: 800,
                            maxHeight: 600,
                          ),
                          title: const Text('Licenses'),
                          content: const FluentLicensePage(),
                          actions: [
                            Button(
                              child: Text(translation.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Text('Licenses'),
                ),
              ),
              spacer,
              FutureBuilder(
                future: getPackageInfo(),
                builder: (ctx, snapshot) =>
                    snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: ProgressBar())
                    : Text(
                        'Version: ${packageInfo.version} (${packageInfo.buildNumber})',
                      ),
              ),
            ],
          ),
        ],
      ),
    ];

    return ScaffoldPage.scrollable(
      header: PageHeader(title: Text(translation.about)),
      children: pageContent,
    );
  }
}

class FluentLicensePage extends StatefulWidget {
  const FluentLicensePage({super.key});

  @override
  State<FluentLicensePage> createState() => _FluentLicensePageState();
}

class _FluentLicensePageState extends State<FluentLicensePage> {
  Future<List<LicenseEntry>>? _licenses;

  @override
  void initState() {
    super.initState();
    _licenses = LicenseRegistry.licenses.toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LicenseEntry>>(
      future: _licenses,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ProgressRing();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Text('Could not load licenses.');
        }
        final licenses = snapshot.data!;
        return ListView.builder(
          itemCount: licenses.length,
          itemBuilder: (context, index) {
            final license = licenses[index];
            return Expander(
              header: Text(license.packages.join(', ')),
              content: SelectableText(
                license.paragraphs.map((p) => p.text).join('\n\n'),
              ),
            );
          },
        );
      },
    );
  }
}
