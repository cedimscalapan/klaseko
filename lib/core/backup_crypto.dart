import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class BackupCrypto {
  static final _cipher = AesGcm.with256bits();
  static Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static Future<String> seal(String data, String password) async {
    final salt = _cipher.newNonce();
    final box = await _cipher.encrypt(
      utf8.encode(data),
      secretKey: await _key(password, salt),
    );
    return jsonEncode({
      'format': 'KlaseKoEncrypted',
      'version': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    });
  }

  static Future<String> open(String data, String password) async {
    final m = jsonDecode(data) as Map<String, dynamic>;
    if (m['format'] != 'KlaseKoEncrypted' || m['version'] != 1)
      throw const FormatException('Unsupported backup format.');
    try {
      final box = SecretBox(
        base64Decode(m['data'] as String),
        nonce: base64Decode(m['nonce'] as String),
        mac: Mac(base64Decode(m['mac'] as String)),
      );
      return utf8.decode(
        await _cipher.decrypt(
          box,
          secretKey: await _key(password, base64Decode(m['salt'] as String)),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('Incorrect password or damaged backup.');
    }
  }
}
