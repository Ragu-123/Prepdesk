import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/services/security/vault_pin_codec.dart';

void main() {
  test('Salted credentials verify the correct PIN and reject other PINs', () {
    final first = VaultPinCodec.encode('123456');
    final second = VaultPinCodec.encode('123456');
    expect(first, isNot(second));
    expect(VaultPinCodec.verify(['123456', first]), isTrue);
    expect(VaultPinCodec.verify(['654321', first]), isFalse);
    expect(VaultPinCodec.verify(['123456', 'pbkdf2-sha256:0:bad:bad']), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('Legacy PIN remains usable for authenticated credential migration', () {
    final old = sha256.convert(utf8.encode('1234')).toString();
    expect(VaultPinCodec.verify(['1234', old]), isTrue);
    expect(VaultPinCodec.verify(['0000', old]), isFalse);
  });
}
