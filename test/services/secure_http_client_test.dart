import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/secure_http_client.dart';
import 'package:joflauncher/services/trusted_roots.dart';

void main() {
  test('the bundled roots parse into a security context', () {
    expect(
      () => bundledRootsSecurityContext(withTrustedRoots: false),
      returnsNormally,
    );
  });

  // ISRG Root X1 (Let's Encrypt), USERTrust ECC (Sectigo) and Amazon Root CA 1
  // are what jofhub, GitHub and cloud.jof.app chain to today.
  test('bundles the roots the launcher hosts chain to', () {
    for (final name in [
      'ISRG Root X1',
      'USERTrust ECC Certification Authority',
      'Amazon Root CA 1',
    ]) {
      expect(bundledRootCertificatesPem, contains('# $name\n'), reason: name);
    }
    expect('BEGIN CERTIFICATE'.allMatches(bundledRootCertificatesPem),
        hasLength(11));
  });
}
