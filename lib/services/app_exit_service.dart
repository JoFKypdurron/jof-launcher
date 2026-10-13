import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;

class AppExitService {
  Future<void> requestExit() async {
    if (kIsWeb) return;

    // On desktop, a hard exit is acceptable for this launcher.
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      exit(0);
    }

    // On mobile, request the app to be popped.
    await SystemNavigator.pop();
  }
}
