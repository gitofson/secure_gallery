import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Služba pro šifrování a dešifrování obrázků pomocí AES
class EncryptionService {
  static const _storage = FlutterSecureStorage();
  static const _keyStorageKey = 'encryption_key';
  static const _ivStorageKey = 'encryption_iv';

  static encrypt.Key? _key;
  static encrypt.IV? _iv;
  static encrypt.Encrypter? _encrypter;

  /// Inicializace - načte nebo vytvoří klíč a IV
  static Future<void> initialize() async {
    print('🔑 Inicializace šifrování...');

    // Načtení nebo vytvoření klíče
    String? keyString = await _storage.read(key: _keyStorageKey);
    if (keyString == null) {
      print('🔑 Generuji nový klíč...');
      _key = encrypt.Key.fromLength(32);
      await _storage.write(key: _keyStorageKey, value: base64.encode(_key!.bytes));
    } else {
      print('🔑 Načítám existující klíč...');
      _key = encrypt.Key(base64.decode(keyString));
    }

    // Načtení nebo vytvoření IV
    String? ivString = await _storage.read(key: _ivStorageKey);
    if (ivString == null) {
      print('🔑 Generuji nový IV...');
      _iv = encrypt.IV.fromLength(16);
      await _storage.write(key: _ivStorageKey, value: base64.encode(_iv!.bytes));
    } else {
      print('🔑 Načítám existující IV...');
      _iv = encrypt.IV(base64.decode(ivString));
    }

    _encrypter = encrypt.Encrypter(encrypt.AES(_key!));
    print('✅ Šifrování inicializováno');
  }

  /// Zašifruje data obrázku
  static Uint8List encryptImage(Uint8List imageBytes) {
    if (_encrypter == null) {
      throw Exception('EncryptionService není inicializován! Zavolej initialize() první.');
    }
    final encrypted = _encrypter!.encryptBytes(imageBytes, iv: _iv!);
    return encrypted.bytes;
  }

  /// Dešifruje data obrázku
  static Uint8List decryptImage(Uint8List encryptedBytes) {
    if (_encrypter == null) {
      throw Exception('EncryptionService není inicializován! Zavolej initialize() první.');
    }
    final decrypted = _encrypter!.decryptBytes(
      encrypt.Encrypted(encryptedBytes),
      iv: _iv!,
    );
    return Uint8List.fromList(decrypted);
  }
}
