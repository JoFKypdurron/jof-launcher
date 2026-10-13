import 'package:flutter_test/flutter_test.dart';

import 'package:joflauncher/utils/version.dart';

void main() {
  group('normalizeVersion', () {
    test('strips the tag decoration used by this repo', () {
      expect(normalizeVersion('v1.1.8-launcher'), '1.1.8');
      expect(normalizeVersion('1.1.8'), '1.1.8');
      expect(normalizeVersion('  v1.1.8  '), '1.1.8');
    });
  });

  group('tryParseVersion', () {
    test('parses ordinary versions', () {
      expect(tryParseVersion('1.1.8'), [1, 1, 8]);
      expect(tryParseVersion('v1.1.8-launcher'), [1, 1, 8]);
    });

    test('parses the legacy non-semver tags', () {
      // v1.0.42b-launcher shipped before the scheme settled down.
      expect(tryParseVersion('v1.0.42b-launcher'), [1, 0, 42]);
    });

    test('returns null when there is no version number at all', () {
      expect(tryParseVersion(''), isNull);
      expect(tryParseVersion('   '), isNull);
      expect(tryParseVersion('nightly'), isNull);
      expect(tryParseVersion('v-launcher'), isNull);
    });

    test('tolerates odd segments without throwing', () {
      expect(tryParseVersion('1..3'), [1, 0, 3]);
      expect(tryParseVersion('1.beta.3'), [1, 0, 3]);
    });
  });

  group('compareVersions', () {
    test('orders by numeric segment, not lexically', () {
      // The lexical trap: '1.1.10' < '1.1.9' as strings.
      expect(compareVersions('1.1.10', '1.1.9'), 1);
      expect(compareVersions('1.1.9', '1.1.10'), -1);
      expect(compareVersions('1.2.0', '1.10.0'), -1);
    });

    test('zero-pads unequal segment counts', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.1', '1.2'), 1);
      expect(compareVersions('2', '1.9.9'), 1);
    });

    test('is indifferent to tag decoration', () {
      expect(compareVersions('v1.1.9-launcher', '1.1.9'), 0);
      expect(compareVersions('v1.1.9-launcher', 'v1.1.8-launcher'), 1);
    });

    test('sorts unparseable below parseable, equal to each other', () {
      expect(compareVersions('nightly', '1.0.0'), -1);
      expect(compareVersions('1.0.0', 'nightly'), 1);
      expect(compareVersions('nightly', 'unknown'), 0);
    });
  });

  group('isNewerVersion', () {
    test('true only for a strictly greater parseable version', () {
      expect(isNewerVersion('1.1.9', '1.1.8'), isTrue);
      expect(isNewerVersion('1.1.8', '1.1.8'), isFalse);
      expect(isNewerVersion('1.1.7', '1.1.8'), isFalse);
    });

    test('handles the real upgrade path off a legacy tag', () {
      expect(isNewerVersion('1.1.8', '1.0.42b'), isTrue);
    });

    // The safety property: an unknown running version must not look ancient,
    // or every user with an empty PackageInfo gets offered a bogus update.
    test('refuses to compare when either side is unknown', () {
      expect(isNewerVersion('1.1.9', ''), isFalse);
      expect(isNewerVersion('1.1.9', 'unknown'), isFalse);
      expect(isNewerVersion('', '1.1.8'), isFalse);
    });
  });
}
