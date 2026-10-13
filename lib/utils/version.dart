/// Version parsing and comparison for launcher release checks.
///
/// Deliberately lenient rather than strict semver: released tags have not been
/// consistent (`v1.1.8-launcher`, and older ones like `v1.0.42b-launcher`), and
/// a parser that throws on an unexpected shape would break update checks for
/// whoever is running that build. Nothing here throws.
library;

final RegExp _leadingDigits = RegExp(r'^\d+');

/// Strips the decoration around a released version: the `v` prefix and the
/// `-launcher` suffix used by this repo's tags.
String normalizeVersion(String raw) {
  var value = raw.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  if (value.endsWith('-launcher')) {
    value = value.substring(0, value.length - '-launcher'.length);
  }
  return value.trim();
}

/// Parses [raw] into numeric segments, or null when it holds no version number.
///
/// Each dot-separated segment contributes its leading digits, so the legacy
/// `1.0.42b` parses as `[1, 0, 42]`. A segment with no leading digit
/// contributes 0. Returns null only when no segment had any digits at all,
/// which callers should treat as "unknown", never as "very old".
List<int>? tryParseVersion(String raw) {
  final normalized = normalizeVersion(raw);
  if (normalized.isEmpty) return null;

  final segments = <int>[];
  var sawDigit = false;

  for (final part in normalized.split('.')) {
    final match = _leadingDigits.firstMatch(part.trim());
    if (match == null) {
      segments.add(0);
      continue;
    }
    sawDigit = true;
    segments.add(int.tryParse(match.group(0)!) ?? 0);
  }

  return sawDigit ? segments : null;
}

/// Compares two version strings, returning -1, 0 or 1.
///
/// Shorter versions are zero-padded, so `1.2` equals `1.2.0`. An unparseable
/// version sorts below a parseable one; two unparseable versions are equal.
int compareVersions(String a, String b) {
  final left = tryParseVersion(a);
  final right = tryParseVersion(b);

  if (left == null && right == null) return 0;
  if (left == null) return -1;
  if (right == null) return 1;

  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

/// Whether [candidate] is a strictly newer release than [current].
///
/// Returns false unless *both* versions parse. An unknown running version must
/// not be treated as ancient — that would offer a bogus update to every user
/// whose `PackageInfo` came back empty.
bool isNewerVersion(String candidate, String current) {
  if (tryParseVersion(candidate) == null) return false;
  if (tryParseVersion(current) == null) return false;
  return compareVersions(candidate, current) > 0;
}
