/// `MAS-` + 4 + 1 → `MAS-0001`. Numbers wider than [digits] are kept whole.
String formatRefId(String prefix, int digits, int number) =>
    '$prefix${number.toString().padLeft(digits, '0')}';

/// Offline placeholder until the server assigns a real number: `HOL-TEMP-3`, `MAS-TEMP-1`, `TEMP-2`.
String provisionalRefId(String prefix, int n) {
  final endsAlnum = prefix.isNotEmpty && RegExp(r'[A-Za-z0-9]$').hasMatch(prefix);
  return '${prefix}${endsAlnum ? '-' : ''}TEMP-$n';
}

/// Provisional entries carry a negative [number]; positive numbers are always real.
bool isProvisional(int number) => number < 0;

/// Closes gaps: distinct positive numbers, ascending, map to 1..k. Only numbers that change appear.
Map<int, int> compactionMap(Iterable<int> liveNumbers) {
  final sorted = liveNumbers.where((n) => n > 0).toSet().toList()..sort();
  return {
    for (var i = 0; i < sorted.length; i++)
      if (sorted[i] != i + 1) sorted[i]: i + 1,
  };
}
