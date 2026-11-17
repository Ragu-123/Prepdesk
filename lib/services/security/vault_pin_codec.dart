import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Versioned PBKDF2 credentials; runs in an isolate through VaultService.
class VaultPinCodec {
  static const int iterations = 600000;

  static String encode(String pin) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    return 'pbkdf2-sha256:$iterations:${base64Encode(salt)}:'
        '${base64Encode(_derive(pin, salt, iterations))}';
  }

  static bool verify(List<String> input) {
    final pin = input[0];
    final credential = input[1];
    if (!credential.startsWith('pbkdf2-sha256:')) {
      return _equal(utf8.encode(sha256.convert(utf8.encode(pin)).toString()),
          utf8.encode(credential));
    }
    try {
      final parts = credential.split(':');
      final rounds = int.parse(parts[1]);
      if (parts.length != 4 || rounds < 100000 || rounds > 1000000) return false;
      return _equal(_derive(pin, base64Decode(parts[2]), rounds),
          base64Decode(parts[3]));
    } catch (_) {
      return false;
    }
  }

  static List<int> _derive(String pin, List<int> salt, int rounds) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(block);
    for (var i = 1; i < rounds; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    return result;
  }

  static bool _equal(List<int> a, List<int> b) {
    var difference = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
