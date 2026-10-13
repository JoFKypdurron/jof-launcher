import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// End-to-end encryption for cloud backups.
///
/// Format: `magic(4) + iv(12) + ciphertextAndTag(n)`
/// - magic: ASCII `JOF1`
/// - iv: random 12-byte GCM nonce
/// - ciphertextAndTag: AES-GCM output (ciphertext with auth tag appended)
class BackupEncryption {
  static final Uint8List _magic = Uint8List.fromList(utf8.encode('JOF1'));
  static const int _ivLength = 12;

  static Uint8List encryptBytes({required List<int> plaintext, required String backupId}) {
    final key = _deriveKey(backupId);
    final iv = _randomBytes(_ivLength);

    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final encrypted = encrypter.encryptBytes(plaintext, iv: encrypt.IV(iv));

    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(iv)
      ..add(encrypted.bytes);
    return out.takeBytes();
  }

  static Uint8List decryptBytes({required List<int> encryptedBytes, required String backupId}) {
    final bytes = Uint8List.fromList(encryptedBytes);
    if (bytes.length < _magic.length + _ivLength + 1) {
      throw const FormatException('Encrypted backup is too short');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('Encrypted backup has invalid header');
      }
    }

    final ivStart = _magic.length;
    final ivEnd = ivStart + _ivLength;
    final iv = bytes.sublist(ivStart, ivEnd);
    final payload = bytes.sublist(ivEnd);

    final key = _deriveKey(backupId);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final decrypted = encrypter.decryptBytes(encrypt.Encrypted(payload), iv: encrypt.IV(iv));
    return Uint8List.fromList(decrypted);
  }

  static bool looksEncrypted(List<int> bytes) {
    if (bytes.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static encrypt.Key _deriveKey(String backupId) {
    // `SettingsService` stores SHA-256 hex for the backup id, so this is usually
    // a 64-char hex string. Decode if it looks like hex; otherwise hash.
    final normalized = backupId.trim();
    final isHex = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized);
    if (isHex) {
      return encrypt.Key(Uint8List.fromList(_hexToBytes(normalized)));
    }

    final digest = sha256.convert(utf8.encode(normalized));
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rnd.nextInt(256)));
  }

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
