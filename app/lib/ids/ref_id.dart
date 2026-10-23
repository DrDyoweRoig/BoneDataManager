/// `MAS-` + 4 + 1 → `MAS-0001`. Numbers wider than [digits] are kept whole.
String formatRefId(String prefix, int digits, int number) =>
    '$prefix${number.toString().padLeft(digits, '0')}';
