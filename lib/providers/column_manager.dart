import 'package:flutter/foundation.dart';
import 'user_prefs.dart';

class ColumnManager with ChangeNotifier {
  bool isSearchOpen = false;

  void toggleSearch() {
    isSearchOpen = !isSearchOpen;
    notifyListeners();
  }
}

// –––––––––––––––––––––––––––––––––––––––
class ScrollGroup with ChangeNotifier {
  BibleReference? scrollGroupBibleReference;
  Key? activeColumnKey;

  BibleReference? get getScrollGroupRef {
    return scrollGroupBibleReference;
  }

  set setScrollGroupRef(BibleReference ref) {
    void setScrollGroup() {
      scrollGroupBibleReference = ref;

      notifyListeners();
    }

    if (scrollGroupBibleReference == null) {
      setScrollGroup();
    } else {
      bool same =
          (scrollGroupBibleReference!.bookID == ref.bookID &&
          scrollGroupBibleReference!.chapter == ref.chapter &&
          scrollGroupBibleReference!.verse == ref.verse);

      if (!same) {
        setScrollGroup();
      }
    }
  }

  Key? get getActiveColumnKey {
    return activeColumnKey;
  }

  set setActiveColumnKey(Key? key) {
    // print('set active col key to $key');
    if (activeColumnKey != key) {
      activeColumnKey = key;
    }
  }
}
