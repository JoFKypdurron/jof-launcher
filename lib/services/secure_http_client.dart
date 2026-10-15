import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'trusted_roots.dart';

/// Builds the HTTP clients every service uses for real network access.
///
/// On Windows the client trusts [bundledRootCertificatesPem] on top of the
/// system store; see that file for why. Verification stays fully on: a
/// certificate that does not chain to a trusted root is still rejected.
/// Linux and macOS keep the platform defaults.
http.Client createSecureHttpClient({Duration? connectionTimeout}) {
  if (kIsWeb) return http.Client();

  final client = io.HttpClient(
      context: io.Platform.isWindows ? _windowsContext : null);
  if (connectionTimeout != null) client.connectionTimeout = connectionTimeout;
  return IOClient(client);
}

final io.SecurityContext _windowsContext =
    bundledRootsSecurityContext(withTrustedRoots: true);

/// A context trusting the bundled roots, and the system store too unless
/// [withTrustedRoots] is false. Tests pass false to prove the bundle alone
/// verifies every host, which is the situation on a Windows machine whose
/// root store has not been populated.
@visibleForTesting
io.SecurityContext bundledRootsSecurityContext({required bool withTrustedRoots}) {
  return io.SecurityContext(withTrustedRoots: withTrustedRoots)
    ..setTrustedCertificatesBytes(utf8.encode(bundledRootCertificatesPem));
}
