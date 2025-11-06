// Superscript mapping using Unicode. Extend as needed.
const Map<String, String> supMap = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶',
  '7': '⁷', '8': '⁸', '9': '⁹', '-': '⁻', '–': '⁻',
  // '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
  // common letters used as exponents
  // 'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ',
  // 'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ',
  // 'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ', 'p': 'ᵖ', 'r': 'ʳ',
  // 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
  // 'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
  // 'A': 'ᴬ', 'B': 'ᴮ', 'D': 'ᴰ', 'E': 'ᴱ', 'G': 'ᴳ', 'H': 'ᴴ', 'I': 'ᴵ',
  // 'J': 'ᴶ', 'K': 'ᴷ', 'L': 'ᴸ',
  // 'M': 'ᴹ', 'N': 'ᴺ', 'O': 'ᴼ', 'P': 'ᴾ', 'R': 'ᴿ', 'T': 'ᵀ', 'U': 'ᵁ',
  // 'V': 'ⱽ', 'W': 'ᵂ',
};

String toSuperscript(String input) =>
    input.split('').map((c) => supMap[c] ?? c).join();

String removeDiacritics(String str) {
    var withDia =
        'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    var withoutDia =
        'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }

    return str;
  }


bool isParagraph(String style) {
  // based on verseStyle, is this a new paragraph?
  return style.contains(
    RegExp(
      r'[p,po,pr,cls,pmo,pm,pmc,pmr,pi\d,mi,nb,pc,ph\d,b,mt\d,mte\d,ms\d,mr,s\d*,sr,sp,sd\d,q,q1,q2,qr,qc,qa,qm\d,qd,lh,li\d,lf,lim\d,ip,im,ie,ili]',
    ),
  );
}

bool isHeader(String style) {
  // based on verseStyle, is this a new paragraph?
  return style.contains(RegExp(r'(s\d*|mt\d*|mr|ms\d*|h|toc\d*)'));
}
