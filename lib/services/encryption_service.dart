import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'settings_service.dart';

/// Služba pro šifrování a dešifrování obrázků pomocí AES
class EncryptionService {
  static const _keyFileName = 'encryption_key.bin';
  static const _ivFileName = 'encryption_iv.bin';

  static encrypt.Key? _key;
  static encrypt.IV? _iv;
  static encrypt.Encrypter? _encrypter;

  /// Získá adresář pro uložení klíčů (public external storage)
  static Future<Directory> _getKeyDirectory() async {
    final customPath = await SettingsService.getStoragePath();
    if (customPath != null && customPath.isNotEmpty) {
      return Directory(customPath);
    }
    
    // Výchozí: public external storage (přežije odinstalaci)
    final publicDir = Directory('/storage/emulated/0/SecureGallery');
    if (await publicDir.exists() || await publicDir.create(recursive: true).then((_) => true).catchError((_) => false)) {
      return publicDir;
    }
    
    // Fallback: externí úložiště aplikace
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      return externalDir;
    }
    
    return await getApplicationDocumentsDirectory();
  }

  /// Inicializace - načte nebo vytvoří klíč a IV
  static Future<void> initialize() async {
    print('🔑 Inicializace šifrování...');

    final keyDir = await _getKeyDirectory();
    final keyFile = File('${keyDir.path}/$_keyFileName');
    final ivFile = File('${keyDir.path}/$_ivFileName');

    // Načtení nebo vytvoření klíče
    if (await keyFile.exists()) {
      print('🔑 Načítám existující klíč...');
      final keyBytes = await keyFile.readAsBytes();
      _key = encrypt.Key(Uint8List.fromList(keyBytes));
    } else {
      print('🔑 Generuji nový klíč...');
      _key = encrypt.Key.fromLength(32);
      await keyFile.writeAsBytes(_key!.bytes);
    }

    // Načtení nebo vytvoření IV
    if (await ivFile.exists()) {
      print('🔑 Načítám existující IV...');
      final ivBytes = await ivFile.readAsBytes();
      _iv = encrypt.IV(Uint8List.fromList(ivBytes));
    } else {
      print('🔑 Generuji nový IV...');
      _iv = encrypt.IV.fromLength(16);
      await ivFile.writeAsBytes(_iv!.bytes);
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

  /// Zašifruje text (např. název alba nebo souboru)
  static String encryptText(String plainText) {
    if (_encrypter == null) {
      throw Exception('EncryptionService není inicializován! Zavolej initialize() první.');
    }
    final encrypted = _encrypter!.encrypt(plainText, iv: _iv!);
    return encrypted.base64;
  }

  /// Dešifruje text
  static String decryptText(String encryptedBase64) {
    if (_encrypter == null) {
      throw Exception('EncryptionService není inicializován! Zavolej initialize() první.');
    }
    return _encrypter!.decrypt64(encryptedBase64, iv: _iv!);
  }

  /// Vytvoří anonymní (ale stabilní) název z původního názvu
  /// Stejný vstup → stejný výstup, bez klíče nezjistitelný
  static String anonymizeName(String originalName) {
    if (_key == null) {
      throw Exception('EncryptionService není inicializován! Zavolej initialize() první.');
    }
    final hmac = Hmac(sha256, _key!.bytes);
    final digest = hmac.convert(utf8.encode(originalName));
    return digest.toString().substring(0, 32);
  }
}
