import 'package:flutter_test/flutter_test.dart';

import 'package:joflauncher/models/platform_arch.dart';
import 'package:joflauncher/services/cloud_service.dart';

void main() {
  group('CloudService platform client tarball URL selection', () {
    test('linuxClientTarGzUrl maps arch to expected URLs', () {
      expect(
        CloudService.linuxClientTarGzUrl('1.6.1', LinuxSystemArch.bit32),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.6.1/JoF-linux-x86.tar.gz',
      );
      expect(
        CloudService.linuxClientTarGzUrl('1.6.1', LinuxSystemArch.bit64),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.6.1/JoF-linux-x86_64.tar.gz',
      );
    });

    test('macosClientTarGzUrl maps arch to expected URLs', () {
      expect(
        CloudService.macosClientTarGzUrl('1.6.1', MacosSystemArch.amd),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.6.1/JoF-macos-x86_64.tar.gz',
      );
      expect(
        CloudService.macosClientTarGzUrl('1.6.1', MacosSystemArch.arm),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.6.1/JoF-macos-arm64.tar.gz',
      );
    });

    test('windowsClientZipUrl maps arch to expected URLs', () {
      expect(
        CloudService.windowsClientZipUrl('1.6.1', WindowsSystemArch.bit32),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.6.1/JoF-windows-x86.zip',
      );
      expect(
        CloudService.windowsClientZipUrl('1.6.1', WindowsSystemArch.bit64),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.6.1/JoF-windows-x86_64.zip',
      );
    });

    test('version from the manifest is what ends up in the URL', () {
      expect(
        CloudService.macosClientTarGzUrl('1.7.0', MacosSystemArch.arm),
        'https://github.com/JediofFreedom/JoF_EJK/releases/download/1.7.0/JoF-macos-arm64.tar.gz',
      );
    });
  });
}
