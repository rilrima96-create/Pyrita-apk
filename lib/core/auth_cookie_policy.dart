String? sessionCookieValueForStorage(String setCookieHeader) {
  final nameValue = setCookieHeader.split(';').first.trim();
  if (nameValue.isEmpty) return null;

  final equalsIndex = nameValue.indexOf('=');
  if (equalsIndex <= 0) return null;

  final value = nameValue.substring(equalsIndex + 1);
  if (value.isEmpty) return null;

  final lower = setCookieHeader.toLowerCase();
  if (lower.contains('max-age=0') ||
      lower.contains('expires=thu, 01 jan 1970')) {
    return null;
  }

  return nameValue;
}
