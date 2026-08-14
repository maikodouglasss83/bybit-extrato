import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

/// Erro devolvido pela própria Bybit (retCode != 0).
class BybitException implements Exception {
  BybitException(this.code, this.message);
  final int code;
  final String message;

  /// Chave inválida, expirada ou sem permissão.
  bool get isAuth =>
      code == 10003 || code == 10004 || code == 10005 || code == 33004 || code == 10010;

  /// Relógio do aparelho fora de sincronia com o servidor da Bybit.
  bool get isClockSkew => code == 10002;

  @override
  String toString() => message;
}

/// Cliente da API v5 da Bybit. Só faz leitura — nunca envia ordens nem saques.
class BybitClient {
  BybitClient({
    required this.apiKey,
    required this.apiSecret,
    this.testnet = false,
  });

  final String apiKey;
  final String apiSecret;
  final bool testnet;

  static const _recvWindow = '20000';
  static const _timeout = Duration(seconds: 25);

  /// Depois disso vale conferir o relógio de novo, para acompanhar deriva.
  static const _timeSyncValidity = Duration(minutes: 5);

  /// Diferença entre o relógio do servidor e o do aparelho, em milissegundos.
  ///
  /// A Bybit recusa qualquer requisição que chegue mais de um segundo no
  /// futuro — e a `recv_window` só cobre atraso, nunca adiantamento. Como o
  /// relógio do aparelho costuma derivar alguns segundos, todos os carimbos
  /// de tempo saem daqui, já corrigidos.
  int _timeOffsetMs = 0;
  DateTime? _timeSyncedAt;

  String get _host => testnet ? 'api-testnet.bybit.com' : 'api.bybit.com';

  String _signature(String payload) =>
      Hmac(sha256, utf8.encode(apiSecret)).convert(utf8.encode(payload)).toString();

  /// Carimbo de tempo alinhado ao servidor.
  String _timestamp() =>
      (DateTime.now().millisecondsSinceEpoch + _timeOffsetMs).toString();

  /// Diferença atual entre os relógios, útil para diagnóstico.
  Duration get clockSkew => Duration(milliseconds: -_timeOffsetMs);

  /// Lê a hora do servidor e guarda a diferença para o relógio local.
  Future<void> syncTime() async {
    final res = await http
        .get(Uri.parse('https://$_host/v5/market/time'))
        .timeout(_timeout);
    if (res.statusCode != 200 || res.body.isEmpty) return;

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final serverMs = int.tryParse(body['time']?.toString() ?? '');
    if (serverMs == null || serverMs <= 0) return;

    _timeOffsetMs = serverMs - DateTime.now().millisecondsSinceEpoch;
    _timeSyncedAt = DateTime.now();
  }

  Future<void> _ensureTimeSync({bool force = false}) async {
    final last = _timeSyncedAt;
    final vencido = last == null ||
        DateTime.now().difference(last) > _timeSyncValidity;
    if (!force && !vencido) return;
    try {
      await syncTime();
    } catch (_) {
      // Sem a hora do servidor seguimos com o relógio local: pode funcionar
      // se a diferença for pequena, e o erro 10002 dispara nova tentativa.
    }
  }

  /// A query string precisa ser byte a byte a mesma na assinatura e na URL,
  /// por isso ela é montada uma única vez aqui.
  String _queryString(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  /// Os endpoints do Bybit Card usam POST com o corpo em JSON, e a assinatura
  /// cobre o corpo exatamente como ele é enviado.
  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic> body = const {},
    bool retrying = false,
  }) async {
    await _ensureTimeSync();

    final payload = jsonEncode(body);
    final ts = _timestamp();

    final res = await http
        .post(
          Uri.parse('https://$_host$path'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-BAPI-API-KEY': apiKey,
            'X-BAPI-TIMESTAMP': ts,
            'X-BAPI-RECV-WINDOW': _recvWindow,
            'X-BAPI-SIGN': _signature('$ts$apiKey$_recvWindow$payload'),
          },
          body: payload,
        )
        .timeout(_timeout);

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw BybitException(10003, 'Chave de API rejeitada pela Bybit (${res.statusCode}).');
    }
    if (res.body.isEmpty) {
      throw BybitException(res.statusCode, 'Resposta vazia da Bybit (${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final code = (decoded['retCode'] as num?)?.toInt() ?? -1;

    // O relógio pode ter derivado desde a última sincronia: acerta e repete.
    if (code == 10002 && !retrying) {
      await _ensureTimeSync(force: true);
      return _post(path, body: body, retrying: true);
    }

    if (code != 0) {
      throw BybitException(code, decoded['retMsg']?.toString() ?? 'Erro desconhecido');
    }
    return Map<String, dynamic>.from(decoded['result'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> params = const {},
    bool signed = true,
    bool retrying = false,
  }) async {
    if (signed) await _ensureTimeSync();

    final qs = _queryString(params);
    final url = Uri.parse('https://$_host$path${qs.isEmpty ? '' : '?$qs'}');

    final headers = <String, String>{'Accept': 'application/json'};
    if (signed) {
      final ts = _timestamp();
      headers.addAll({
        'X-BAPI-API-KEY': apiKey,
        'X-BAPI-TIMESTAMP': ts,
        'X-BAPI-RECV-WINDOW': _recvWindow,
        'X-BAPI-SIGN': _signature('$ts$apiKey$_recvWindow$qs'),
      });
    }

    final res = await http.get(url, headers: headers).timeout(_timeout);

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw BybitException(10003, 'Chave de API rejeitada pela Bybit (${res.statusCode}).');
    }
    if (res.statusCode >= 500) {
      throw BybitException(res.statusCode, 'Bybit indisponível no momento (${res.statusCode}).');
    }
    if (res.body.isEmpty) {
      throw BybitException(res.statusCode, 'Resposta vazia da Bybit (${res.statusCode}).');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final code = (body['retCode'] as num?)?.toInt() ?? -1;

    // O relógio pode ter derivado desde a última sincronia: acerta e repete.
    if (code == 10002 && signed && !retrying) {
      await _ensureTimeSync(force: true);
      return _get(path, params: params, signed: signed, retrying: true);
    }

    if (code != 0) {
      throw BybitException(code, body['retMsg']?.toString() ?? 'Erro desconhecido');
    }
    return Map<String, dynamic>.from(body['result'] as Map? ?? const {});
  }

  /// Confere se a chave é válida antes de salvar.
  Future<void> ping() => _get('/v5/account/wallet-balance', params: {'accountType': 'UNIFIED'});

  /// Depósitos internos (fora da blockchain), como compras em reais.
  Future<List<LedgerEntry>> internalDeposits({int limit = 50}) async {
    final result = await _get('/v5/asset/deposit/query-internal-record', params: {'limit': '$limit'});
    final rows = (result['rows'] as List?) ?? const [];
    return rows
        .map((e) => LedgerEntry.fromDeposit(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<WalletSnapshot> walletBalance({String accountType = 'UNIFIED'}) async {
    final result = await _get('/v5/account/wallet-balance', params: {'accountType': accountType});
    final list = (result['list'] as List?) ?? const [];
    if (list.isEmpty) return WalletSnapshot.empty();
    return WalletSnapshot.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  /// Extrato unificado. Devolve a página e o cursor para a próxima.
  Future<LedgerPage> transactionLog({
    String? cursor,
    int limit = 50,
    String accountType = 'UNIFIED',
  }) async {
    final params = <String, String>{
      'accountType': accountType,
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final result = await _get('/v5/account/transaction-log', params: params);
    final list = (result['list'] as List?) ?? const [];
    return LedgerPage(
      entries: list
          .map((e) => LedgerEntry.fromTransactionLog(Map<String, dynamic>.from(e as Map)))
          .toList(),
      nextCursor: result['nextPageCursor']?.toString(),
    );
  }

  /// Saldos da carteira de fundos, que não aparecem no saldo unificado.
  /// O valor em dólar não vem na resposta e é calculado pelo app.
  Future<List<CoinBalance>> fundingBalance() async {
    final result = await _get(
      '/v5/asset/transfer/query-account-coins-balance',
      params: {'accountType': 'FUND'},
    );
    final list = (result['balance'] as List?) ?? const [];
    return list
        .map((e) => CoinBalance.fromFunding(Map<String, dynamic>.from(e as Map)))
        .where((c) => c.walletBalance.abs() > 1e-12)
        .toList();
  }

  /// Transferências entre as carteiras da própria conta.
  Future<LedgerPage> internalTransfers({String? cursor, int limit = 50}) async {
    final params = <String, String>{
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final result = await _get('/v5/asset/transfer/query-inter-transfer-list', params: params);
    final list = (result['list'] as List?) ?? const [];
    return LedgerPage(
      entries: list
          .map((e) => LedgerEntry.fromInternalTransfer(Map<String, dynamic>.from(e as Map)))
          .toList(),
      nextCursor: result['nextPageCursor']?.toString(),
    );
  }

  Future<List<LedgerEntry>> deposits({int limit = 50}) async {
    final result = await _get('/v5/asset/deposit/query-record', params: {'limit': '$limit'});
    final rows = (result['rows'] as List?) ?? const [];
    return rows
        .map((e) => LedgerEntry.fromDeposit(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<LedgerEntry>> withdrawals({int limit = 50}) async {
    final result = await _get('/v5/asset/withdraw/query-record', params: {'limit': '$limit'});
    final rows = (result['rows'] as List?) ?? const [];
    return rows
        .map((e) => LedgerEntry.fromWithdraw(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Compras do Bybit Card. A API só expõe as transações através do histórico
  /// de recompensas, que traz estabelecimento, valor e categoria de cada uma.
  ///
  /// O endpoint aceita até 500 por página, então o histórico inteiro costuma
  /// caber em uma ou duas chamadas.
  Future<CardPage> cardTransactions({int page = 1, int pageSize = 500}) async {
    final result = await _post(
      '/v5/card/reward/points/records',
      body: {'pageNo': page, 'pageSize': pageSize},
    );
    final data = (result['data'] as List?) ?? const [];
    final total = (result['totalCount'] as num?)?.toInt() ?? 0;

    // O histórico de recompensas mistura compras com movimentos de pontos
    // (resgate, bônus, expiração). Estes vêm sem valor, sem estabelecimento e
    // com a data zerada — não são gasto e não podem virar lançamento.
    final compras = data
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((j) =>
            asDouble(j['transactionAmount']) > 0 &&
            (int.tryParse(j['transactionDate']?.toString() ?? '') ?? 0) > 0)
        .toList();

    return CardPage(
      entries: compras.map(LedgerEntry.fromCardTransaction).toList(),
      page: page,
      pageSize: pageSize,
      totalCount: total,
    );
  }

  /// Pontos acumulados e teto de cashback do cartão.
  Future<CardRewards> cardRewards() async {
    final balance = await _post('/v5/card/reward/points/balance');
    var rewards = CardRewards.fromBalance(balance);
    try {
      final tier = await _post('/v5/card/reward/points/tier');
      rewards = rewards.copyWithTier(tier);
    } catch (_) {
      // O teto é informação extra: sem ele, os pontos ainda aparecem.
    }
    return rewards;
  }

  /// Preços spot em USDT, usados para converter saldos que a Bybit não precifica.
  Future<Map<String, double>> spotPrices() async {
    final result = await _get('/v5/market/tickers', params: {'category': 'spot'}, signed: false);
    final list = (result['list'] as List?) ?? const [];
    final prices = <String, double>{};
    for (final raw in list) {
      final t = Map<String, dynamic>.from(raw as Map);
      final symbol = t['symbol']?.toString() ?? '';
      if (!symbol.endsWith('USDT')) continue;
      prices[symbol.substring(0, symbol.length - 4)] = asDouble(t['lastPrice']);
    }
    prices['USDT'] = 1;
    prices['USDC'] = prices['USDC'] ?? 1;
    return prices;
  }
}

class LedgerPage {
  LedgerPage({required this.entries, this.nextCursor});
  final List<LedgerEntry> entries;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

/// Página do extrato do cartão, que usa numeração em vez de cursor.
class CardPage {
  CardPage({
    required this.entries,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<LedgerEntry> entries;
  final int page;
  final int pageSize;
  final int totalCount;

  bool get hasMore => entries.isNotEmpty && page * pageSize < totalCount;
}
