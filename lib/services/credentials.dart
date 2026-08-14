import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credenciais da API, guardadas apenas neste dispositivo.
class Credentials {
  const Credentials({
    required this.apiKey,
    required this.apiSecret,
    this.testnet = false,
  });

  final String apiKey;
  final String apiSecret;
  final bool testnet;

  bool get isValid => apiKey.trim().isNotEmpty && apiSecret.trim().isNotEmpty;

  /// Só os últimos caracteres, para exibir sem revelar a chave inteira.
  String get maskedKey {
    final k = apiKey.trim();
    if (k.length <= 4) return '••••';
    return '${'•' * 6}${k.substring(k.length - 4)}';
  }
}

/// Persistência criptografada das credenciais (Keychain/Keystore no mobile,
/// DPAPI no Windows, WebCrypto no navegador).
class CredentialsStore {
  // A partir da v11 o plugin já usa AES-GCM com chave no KeyStore por padrão.
  static const _storage = FlutterSecureStorage();

  static const _kKey = 'bybit_api_key';
  static const _kSecret = 'bybit_api_secret';
  static const _kTestnet = 'bybit_testnet';

  Future<Credentials?> load() async {
    try {
      final key = await _storage.read(key: _kKey);
      final secret = await _storage.read(key: _kSecret);
      if (key == null || secret == null || key.isEmpty || secret.isEmpty) return null;
      return Credentials(
        apiKey: key,
        apiSecret: secret,
        testnet: (await _storage.read(key: _kTestnet)) == 'true',
      );
    } catch (_) {
      // Cofre indisponível: o app segue pedindo as credenciais de novo.
      return null;
    }
  }

  Future<void> save(Credentials c) async {
    await _storage.write(key: _kKey, value: c.apiKey.trim());
    await _storage.write(key: _kSecret, value: c.apiSecret.trim());
    await _storage.write(key: _kTestnet, value: '${c.testnet}');
  }

  Future<void> clear() async {
    await _storage.delete(key: _kKey);
    await _storage.delete(key: _kSecret);
    await _storage.delete(key: _kTestnet);
  }
}
