/// Maps a free-text degree name, such as "B.Tech" or "MBA", to the level used
/// by the degree dropdown.
String normalizeDegree(Object? value) {
  if (value is! String) return 'Other';
  final text = value
      .toLowerCase()
      .replaceAll('.', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      // Join spelled-out abbreviations: "b tech" -> "btech", "ph d" -> "phd".
      .replaceAllMapped(
        RegExp(r'\b([bm]) (tech|e|sc|s|a|com|ca|ba|arch|pharm|ed|phil)\b'),
        (match) => '${match[1]}${match[2]}',
      )
      .replaceAll(RegExp(r'\bph d\b'), 'phd');

  if (text.contains('diploma')) return 'Other';
  if (RegExp(r'\b(phd|dphil)\b|doctor').hasMatch(text)) return 'PhD';
  if (text.contains('master') ||
      RegExp(r'^(mtech|me|msc|ms|ma|mcom|mca|mba|march|mpharm|med|mphil)\b')
          .hasMatch(text)) {
    return 'Master\'s';
  }
  if (text.contains('bachelor') ||
      RegExp(r'^(btech|be|bsc|bs|ba|bcom|bca|bba|barch|bpharm|bed|llb|mbbs)\b')
          .hasMatch(text)) {
    return 'Bachelor\'s';
  }
  return 'Other';
}
