import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'settings_service.dart';

/// Service for encrypting and decrypting images using AES
class EncryptionService {
  static const _keyFileName = 'encryption_key.bin';
  static const _ivFileName = 'encryption_iv.bin';

  static encrypt.Key? _key;
  static encrypt.IV? _iv;
  static encrypt.Encrypter? _encrypter;

  /// Gets the directory for key storage (public external storage)
  static Future<Directory> _getKeyDirectory() async {
    final customPath = await SettingsService.getStoragePath();
    if (customPath != null && customPath.isNotEmpty) {
      return Directory(customPath);
    }
    
    // Default: public external storage (survives uninstall)
    final publicDir = Directory('/storage/emulated/0/SecureGallery');
    if (await publicDir.exists() || await publicDir.create(recursive: true).then((_) => true).catchError((_) => false)) {
      return publicDir;
    }
    
    // Fallback: app external storage
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      return externalDir;
    }
    
    return await getApplicationDocumentsDirectory();
  }

  /// Initialization - loads or creates the key and IV
  static Future<void> initialize() async {
    print('🔑 Initializing encryption...');

    final keyDir = await _getKeyDirectory();
    final keyFile = File('${keyDir.path}/$_keyFileName');
    final ivFile = File('${keyDir.path}/$_ivFileName');

    // Load or create the key
    if (await keyFile.exists()) {
      print('🔑 Loading existing key...');
      final keyBytes = await keyFile.readAsBytes();
      _key = encrypt.Key(Uint8List.fromList(keyBytes));
    } else {
      print('🔑 Generating new key...');
      _key = encrypt.Key.fromLength(32);
      await keyFile.writeAsBytes(_key!.bytes);
    }

    // Load or create the IV
    if (await ivFile.exists()) {
      print('🔑 Loading existing IV...');
      final ivBytes = await ivFile.readAsBytes();
      _iv = encrypt.IV(Uint8List.fromList(ivBytes));
    } else {
      print('🔑 Generating new IV...');
      _iv = encrypt.IV.fromLength(16);
      await ivFile.writeAsBytes(_iv!.bytes);
    }

    _encrypter = encrypt.Encrypter(encrypt.AES(_key!));
    print('✅ Encryption initialized');
  }

  /// Encrypts image data
  static Uint8List encryptImage(Uint8List imageBytes) {
    if (_encrypter == null) {
      throw Exception('EncryptionService is not initialized! Call initialize() first.');
    }
    final encrypted = _encrypter!.encryptBytes(imageBytes, iv: _iv!);
    return encrypted.bytes;
  }

  /// Decrypts image data
  static Uint8List decryptImage(Uint8List encryptedBytes) {
    if (_encrypter == null) {
      throw Exception('EncryptionService is not initialized! Call initialize() first.');
    }
    final decrypted = _encrypter!.decryptBytes(
      encrypt.Encrypted(encryptedBytes),
      iv: _iv!,
    );
    return Uint8List.fromList(decrypted);
  }

  /// Encrypts text (e.g. album or file name)
  static String encryptText(String plainText) {
    if (_encrypter == null) {
      throw Exception('EncryptionService is not initialized! Call initialize() first.');
    }
    final encrypted = _encrypter!.encrypt(plainText, iv: _iv!);
    return encrypted.base64;
  }

  /// Decrypts text
  static String decryptText(String encryptedBase64) {
    if (_encrypter == null) {
      throw Exception('EncryptionService is not initialized! Call initialize() first.');
    }
    return _encrypter!.decrypt64(encryptedBase64, iv: _iv!);
  }

  /// Creates an anonymous (but stable) name from the original name
  /// Same input → same output, undiscoverable without the key
  static String anonymizeName(String originalName) {
    if (_key == null) {
      throw Exception('EncryptionService is not initialized! Call initialize() first.');
    }
    final hmac = Hmac(sha256, _key!.bytes);
    final digest = hmac.convert(utf8.encode(originalName));
    return digest.toString().substring(0, 32);
  }
}
