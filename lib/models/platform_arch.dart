enum LinuxSystemArch {
  bit32,
  bit64,
}

enum MacosSystemArch {
  amd,
  arm,
}

extension LinuxSystemArchCodec on LinuxSystemArch {
  String get persistedValue {
    return switch (this) {
      LinuxSystemArch.bit32 => '32bit',
      LinuxSystemArch.bit64 => '64bit',
    };
  }

  static LinuxSystemArch? tryParse(String? value) {
    return switch (value) {
      '32bit' => LinuxSystemArch.bit32,
      '64bit' => LinuxSystemArch.bit64,
      _ => null,
    };
  }
}

extension MacosSystemArchCodec on MacosSystemArch {
  String get persistedValue {
    return switch (this) {
      MacosSystemArch.amd => 'amd',
      MacosSystemArch.arm => 'arm',
    };
  }

  static MacosSystemArch? tryParse(String? value) {
    return switch (value) {
      'amd' => MacosSystemArch.amd,
      'arm' => MacosSystemArch.arm,
      _ => null,
    };
  }
}

enum WindowsSystemArch {
  bit32,
  bit64,
}

extension WindowsSystemArchCodec on WindowsSystemArch {
  String get persistedValue {
    return switch (this) {
      WindowsSystemArch.bit32 => '32bit',
      WindowsSystemArch.bit64 => '64bit',
    };
  }

  static WindowsSystemArch? tryParse(String? value) {
    return switch (value) {
      '32bit' => WindowsSystemArch.bit32,
      '64bit' => WindowsSystemArch.bit64,
      _ => null,
    };
  }
}
