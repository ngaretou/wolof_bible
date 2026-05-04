import 'dart:io';
import 'package:xml/xml.dart';

// For troubleshooting XML parsing for Changes

void main() async {
  final fileContent = await File('project/usfm_bible.appDef').readAsString();
  final realDoc = XmlDocument.parse(fileContent);
  final xmlChanges = realDoc.findAllElements('change');
  for (var xmlChange in xmlChanges) {
    if (xmlChange.getElement('name')?.innerText ==
        'extra stars in footnote contexts') {
      String k = xmlChange.getElement('find')!.innerText.toString();
      String r = xmlChange.getElement('replace')!.innerText.toString();
      print("Raw K: $k");
      print("Raw R: $r");

      String findString = k.replaceAll(r'\', '\\');
      print("FindString: $findString");

      String bookText = "nocturnes, *quelqu'un";
      print("Original bookText: $bookText");

      bookText = bookText.replaceAllMapped(RegExp(findString), (match) {
        return r.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
          int groupNum = int.parse(m.group(1)!);
          if (groupNum <= match.groupCount) {
            return match.group(groupNum) ?? '';
          }
          return m.group(0)!;
        });
      });
      print("New bookText: $bookText");
    }
  }
}
