import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/url_opener_service.dart';

void main() {
  const url = 'https://github.com/JoFKypdurron/jof-launcher/releases/tag/v1.2.0?a=1&b=2';

  Future<List<String>> commandFor(String os) async {
    List<String>? invoked;
    final opener = UrlOpenerService(
      operatingSystemOverride: os,
      runProcess: (executable, args) async {
        invoked = [executable, ...args];
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(await opener.open(url), isTrue);
    return invoked!;
  }

  test('uses the platform URL handler', () async {
    expect(await commandFor('macos'), ['open', url]);
    expect(await commandFor('linux'), ['xdg-open', url]);
    expect(await commandFor('windows'),
        ['rundll32', 'url.dll,FileProtocolHandler', url]);
  });

  test('reports a non-zero exit as failure', () async {
    final opener = UrlOpenerService(
      operatingSystemOverride: 'windows',
      runProcess: (_, _) async => ProcessResult(0, 1, '', ''),
    );
    expect(await opener.open(url), isFalse);
  });

  test('refuses anything but http(s)', () async {
    final opener = UrlOpenerService(
      operatingSystemOverride: 'windows',
      runProcess: (_, _) async => fail('must not run'),
    );
    expect(await opener.open('file:///C:/Windows/System32/calc.exe'), isFalse);
    expect(await opener.open('-https://example.com'), isFalse);
  });
}
