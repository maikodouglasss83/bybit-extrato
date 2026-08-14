import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Cotação USD → BRL, para mostrar os valores em reais.
class FxService {
  static final _uri = Uri.parse('https://economia.awesomeapi.com.br/json/last/USD-BRL');

  /// Devolve `null` se a cotação não estiver disponível — o app cai para USD.
  Future<double?> usdToBrl() async {
    try {
      final res = await http.get(_uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final quote = body['USDBRL'];
      if (quote is! Map) return null;
      final rate = asDouble(quote['bid']);
      return rate > 0 ? rate : null;
    } catch (_) {
      return null;
    }
  }
}
