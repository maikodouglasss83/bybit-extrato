// Modelos de dados do app, montados a partir das respostas da API v5 da Bybit.

import 'util/categorizer.dart';

double asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  return double.tryParse(s) ?? 0;
}

/// Primeiro carimbo de tempo utilizável da lista. A Bybit manda "0" quando
/// ainda não fechou o lançamento, e zero viraria 1970 na tela.
dynamic _firstTimestamp(List<dynamic> candidates) {
  for (final c in candidates) {
    final ms = int.tryParse(c?.toString() ?? '') ?? 0;
    if (ms > 0) return c;
  }
  return 0;
}

DateTime asTime(dynamic v) {
  final ms = int.tryParse(v?.toString() ?? '') ?? 0;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Em qual carteira da Bybit o saldo está.
enum BybitAccount { unified, funding }

String accountLabel(BybitAccount a) =>
    a == BybitAccount.unified ? 'Conta unificada' : 'Conta de fundos';

/// Saldo de uma moeda dentro de uma das carteiras.
class CoinBalance {
  CoinBalance({
    required this.coin,
    required this.walletBalance,
    required this.equity,
    required this.usdValue,
    required this.unrealisedPnl,
    required this.availableToWithdraw,
    this.account = BybitAccount.unified,
  });

  final String coin;
  final double walletBalance;
  final double equity;
  final double usdValue;
  final double unrealisedPnl;
  final double availableToWithdraw;
  final BybitAccount account;

  factory CoinBalance.fromJson(Map<String, dynamic> j) => CoinBalance(
        coin: j['coin']?.toString() ?? '?',
        walletBalance: asDouble(j['walletBalance']),
        equity: asDouble(j['equity']),
        usdValue: asDouble(j['usdValue']),
        unrealisedPnl: asDouble(j['unrealisedPnl']),
        availableToWithdraw: asDouble(j['availableToWithdraw']),
      );

  /// A carteira de fundos não devolve o valor em dólar: ele é calculado depois,
  /// com as cotações, via [withUsdValue].
  factory CoinBalance.fromFunding(Map<String, dynamic> j) {
    final balance = asDouble(j['walletBalance']);
    return CoinBalance(
      coin: j['coin']?.toString() ?? '?',
      walletBalance: balance,
      equity: balance,
      usdValue: 0,
      unrealisedPnl: 0,
      availableToWithdraw: asDouble(j['transferBalance']),
      account: BybitAccount.funding,
    );
  }

  CoinBalance withUsdValue(double value) => CoinBalance(
        coin: coin,
        walletBalance: walletBalance,
        equity: equity,
        usdValue: value,
        unrealisedPnl: unrealisedPnl,
        availableToWithdraw: availableToWithdraw,
        account: account,
      );
}

/// Retrato da conta em um instante.
class WalletSnapshot {
  WalletSnapshot({
    required this.accountType,
    required this.totalEquity,
    required this.totalWalletBalance,
    required this.totalAvailableBalance,
    required this.totalPerpUPL,
    required this.coins,
  });

  final String accountType;
  final double totalEquity;
  final double totalWalletBalance;
  final double totalAvailableBalance;
  final double totalPerpUPL;
  final List<CoinBalance> coins;

  static WalletSnapshot empty() => WalletSnapshot(
        accountType: '-',
        totalEquity: 0,
        totalWalletBalance: 0,
        totalAvailableBalance: 0,
        totalPerpUPL: 0,
        coins: const [],
      );

  factory WalletSnapshot.fromJson(Map<String, dynamic> j) {
    final rawCoins = (j['coin'] as List?) ?? const [];
    final coins = rawCoins
        .map((c) => CoinBalance.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList()
      ..sort((a, b) => b.usdValue.compareTo(a.usdValue));
    return WalletSnapshot(
      accountType: j['accountType']?.toString() ?? 'UNIFIED',
      totalEquity: asDouble(j['totalEquity']),
      totalWalletBalance: asDouble(j['totalWalletBalance']),
      totalAvailableBalance: asDouble(j['totalAvailableBalance']),
      totalPerpUPL: asDouble(j['totalPerpUPL']),
      coins: coins,
    );
  }

  /// Só as moedas com algum saldo relevante.
  List<CoinBalance> get activeCoins =>
      coins.where((c) => c.equity.abs() > 1e-12 || c.usdValue.abs() > 1e-9).toList();
}

/// Situação do programa de recompensas do Bybit Card.
class CardRewards {
  const CardRewards({
    required this.availablePoints,
    required this.pendingPoints,
    required this.usedLimit,
    required this.limit,
    required this.limitUnit,
  });

  final int availablePoints;
  final int pendingPoints;

  /// Quanto do teto mensal de cashback já foi usado.
  final double usedLimit;
  final double limit;
  final String limitUnit;

  static const empty = CardRewards(
    availablePoints: 0,
    pendingPoints: 0,
    usedLimit: 0,
    limit: 0,
    limitUnit: 'USD',
  );

  bool get hasData => availablePoints > 0 || pendingPoints > 0 || limit > 0;

  double get limitProgress => limit <= 0 ? 0 : (usedLimit / limit).clamp(0, 1);

  CardRewards copyWithTier(Map<String, dynamic> j) => CardRewards(
        availablePoints: availablePoints,
        pendingPoints: pendingPoints,
        usedLimit: asDouble(j['usedLimit']),
        limit: asDouble(j['limit']),
        limitUnit: j['unit']?.toString() ?? 'USD',
      );

  factory CardRewards.fromBalance(Map<String, dynamic> j) => CardRewards(
        availablePoints: int.tryParse(j['availablePoint']?.toString() ?? '') ?? 0,
        pendingPoints: int.tryParse(j['pendingPoint']?.toString() ?? '') ?? 0,
        usedLimit: 0,
        limit: 0,
        limitUnit: 'USD',
      );
}

/// Natureza de um lançamento, usada para escolher ícone, cor e rótulo.
enum LedgerKind {
  deposit,
  withdraw,
  trade,
  fee,
  funding,
  transferIn,
  transferOut,
  internalTransfer,
  cardPurchase,
  cardRefund,
  interest,
  bonus,
  settlement,
  other,
}

/// Um lançamento do extrato, vindo do transaction log, de depósitos ou de saques.
class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.time,
    required this.rawType,
    required this.kind,
    required this.coin,
    required this.change,
    required this.fee,
    required this.source,
    this.balanceAfter,
    this.symbol,
    this.side,
    this.status,
    this.txId,
    this.note,
    this.neutral = false,
    this.category,
    this.cardLast4,
    this.points,
  });

  final String id;
  final DateTime time;
  final String rawType;
  final LedgerKind kind;
  final String coin;

  /// Positivo = entrou na conta. Negativo = saiu.
  final double change;
  final double fee;
  final double? balanceAfter;
  final String? symbol;
  final String? side;
  final String? status;
  final String? txId;

  /// Texto auxiliar, como o caminho de uma transferência entre carteiras.
  final String? note;

  /// Movimentação entre carteiras do próprio usuário: aparece no extrato, mas
  /// não conta como entrada nem como saída de patrimônio.
  final bool neutral;

  /// Ramo do estabelecimento, quando a compra veio do cartão.
  final String? category;

  /// Últimos dígitos do cartão usado.
  final String? cardLast4;

  /// Pontos de recompensa gerados pela compra.
  final int? points;

  /// De onde veio: `log`, `deposit`, `withdraw`, `transfer` ou `card`.
  final String source;

  bool get isIn => change >= 0;

  bool get isCard =>
      kind == LedgerKind.cardPurchase || kind == LedgerKind.cardRefund;

  /// A Bybit mantém só uns seis meses de histórico, então o que já foi visto
  /// é guardado no dispositivo — daí a necessidade de ida e volta em JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.millisecondsSinceEpoch,
        'rawType': rawType,
        'kind': kind.name,
        'coin': coin,
        'change': change,
        'fee': fee,
        'source': source,
        if (balanceAfter != null) 'balanceAfter': balanceAfter,
        if (symbol != null) 'symbol': symbol,
        if (side != null) 'side': side,
        if (status != null) 'status': status,
        if (txId != null) 'txId': txId,
        if (note != null) 'note': note,
        if (neutral) 'neutral': true,
        if (category != null) 'category': category,
        if (cardLast4 != null) 'cardLast4': cardLast4,
        if (points != null) 'points': points,
      };

  factory LedgerEntry.fromCache(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'].toString(),
        time: DateTime.fromMillisecondsSinceEpoch(
          (j['time'] as num?)?.toInt() ?? 0,
        ),
        rawType: j['rawType']?.toString() ?? '',
        kind: LedgerKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => LedgerKind.other,
        ),
        coin: j['coin']?.toString() ?? '?',
        change: asDouble(j['change']),
        fee: asDouble(j['fee']),
        source: j['source']?.toString() ?? 'cache',
        balanceAfter:
            j['balanceAfter'] == null ? null : asDouble(j['balanceAfter']),
        symbol: j['symbol']?.toString(),
        side: j['side']?.toString(),
        status: j['status']?.toString(),
        txId: j['txId']?.toString(),
        note: j['note']?.toString(),
        neutral: j['neutral'] == true,
        category: j['category']?.toString(),
        cardLast4: j['cardLast4']?.toString(),
        points: (j['points'] as num?)?.toInt(),
      );

  /// Extrato unificado da conta (trades, taxas, funding, transferências…).
  factory LedgerEntry.fromTransactionLog(Map<String, dynamic> j) {
    final type = j['type']?.toString() ?? '';
    return LedgerEntry(
      id: j['id']?.toString() ?? '${j['transactionTime']}-$type-${j['currency']}',
      time: asTime(j['transactionTime']),
      rawType: type,
      kind: _kindFromLogType(type),
      coin: j['currency']?.toString() ?? '?',
      change: asDouble(j['change']),
      fee: asDouble(j['fee']),
      balanceAfter: j['cashBalance'] == null ? null : asDouble(j['cashBalance']),
      symbol: (j['symbol']?.toString().isEmpty ?? true) ? null : j['symbol'].toString(),
      side: (j['side']?.toString().isEmpty ?? true) ? null : j['side'].toString(),
      source: 'log',
    );
  }

  factory LedgerEntry.fromDeposit(Map<String, dynamic> j) {
    final amount = asDouble(j['amount']);
    return LedgerEntry(
      id: 'dep-${j['txID'] ?? j['successAt']}-${j['coin']}',
      time: asTime(j['successAt']),
      rawType: 'DEPOSIT',
      kind: LedgerKind.deposit,
      coin: j['coin']?.toString() ?? '?',
      change: amount,
      fee: asDouble(j['depositFee']),
      status: _depositStatus(j['status']),
      txId: j['txID']?.toString(),
      source: 'deposit',
    );
  }

  /// Compra no Bybit Card. Os registros vêm do histórico de pontos, que é
  /// onde a API expõe cada transação com estabelecimento e valor.
  factory LedgerEntry.fromCardTransaction(Map<String, dynamic> j) {
    final amount = asDouble(j['transactionAmount']);
    // side "2" marca estorno; qualquer outro valor é compra.
    final isRefund = j['side']?.toString() == '2';
    final merchant = (j['merchName']?.toString() ?? '').trim();
    final city = (j['merchCity']?.toString() ?? '').trim();

    return LedgerEntry(
      id: 'card-${j['transactionId'] ?? j['outOrderId']}',
      // A data da compra pode vir zerada enquanto a Bybit não fecha o
      // lançamento; nesse caso vale quando o registro foi criado.
      time: asTime(_firstTimestamp([j['transactionDate'], j['createTime']])),
      rawType: 'CARD',
      kind: isRefund ? LedgerKind.cardRefund : LedgerKind.cardPurchase,
      coin: j['basicCurrency']?.toString() ?? 'BRL',
      change: isRefund ? amount.abs() : -amount.abs(),
      fee: 0,
      note: merchant.isEmpty ? null : merchant,
      // A Bybit não preenche a categoria, então ela é deduzida do nome do
      // estabelecimento; se um dia vier preenchida, tem prioridade.
      category: categorizeMerchant(
        merchant,
        apiCategory: _cleanCategory(j['merchCategoryDesc']?.toString()),
      ),
      cardLast4: (j['pan4']?.toString().isEmpty ?? true) ? null : j['pan4'].toString(),
      points: (j['point'] as num?)?.toInt(),
      status: city.isEmpty ? null : city,
      source: 'card',
    );
  }

  /// Transferência entre a carteira unificada e a de fundos.
  factory LedgerEntry.fromInternalTransfer(Map<String, dynamic> j) {
    String label(String? raw) {
      switch (raw?.toUpperCase()) {
        case 'FUND':
          return 'Fundos';
        case 'UNIFIED':
          return 'Unificada';
        case 'CONTRACT':
          return 'Derivativos';
        case 'SPOT':
          return 'Spot';
        default:
          return raw ?? '?';
      }
    }

    final from = label(j['fromAccountType']?.toString());
    final to = label(j['toAccountType']?.toString());

    return LedgerEntry(
      id: 'tr-${j['transferId']}',
      time: asTime(j['timestamp']),
      rawType: 'INTERNAL_TRANSFER',
      kind: LedgerKind.internalTransfer,
      coin: j['coin']?.toString() ?? '?',
      change: asDouble(j['amount']),
      fee: 0,
      status: j['status']?.toString() == 'SUCCESS' ? 'Concluída' : j['status']?.toString(),
      note: '$from → $to',
      neutral: true,
      source: 'transfer',
    );
  }

  factory LedgerEntry.fromWithdraw(Map<String, dynamic> j) {
    final amount = asDouble(j['amount']);
    return LedgerEntry(
      id: 'wd-${j['withdrawId'] ?? j['createTime']}-${j['coin']}',
      time: asTime(j['createTime']),
      rawType: 'WITHDRAW',
      kind: LedgerKind.withdraw,
      coin: j['coin']?.toString() ?? '?',
      change: -amount,
      fee: asDouble(j['withdrawFee']),
      status: j['status']?.toString(),
      txId: j['txID']?.toString(),
      source: 'withdraw',
    );
  }
}

LedgerKind _kindFromLogType(String type) {
  switch (type.toUpperCase()) {
    case 'TRANSFER_IN':
      return LedgerKind.transferIn;
    case 'TRANSFER_OUT':
      return LedgerKind.transferOut;
    case 'TRADE':
    case 'CURRENCY_BUY':
    case 'CURRENCY_SELL':
      return LedgerKind.trade;
    case 'SETTLEMENT':
      return LedgerKind.funding;
    case 'DELIVERY':
    case 'LIQUIDATION':
      return LedgerKind.settlement;
    case 'INTEREST':
      return LedgerKind.interest;
    case 'BONUS':
    case 'AIRDROP':
      return LedgerKind.bonus;
    case 'FEE_REFUND':
      return LedgerKind.fee;
    default:
      return LedgerKind.other;
  }
}

/// A Bybit devolve a categoria em caixa alta e com códigos; deixa legível.
String? _cleanCategory(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  return t
      .split(RegExp(r'\s+'))
      .map((w) => w.length <= 2
          ? w.toUpperCase()
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

String _depositStatus(dynamic raw) {
  switch (int.tryParse(raw?.toString() ?? '')) {
    case 1:
      return 'Aguardando confirmação';
    case 2:
      return 'Processando';
    case 3:
      return 'Concluído';
    case 4:
      return 'Falhou';
    default:
      return 'Desconhecido';
  }
}

/// Rótulo em português para exibir na lista.
String kindLabel(LedgerKind kind, String rawType) {
  switch (kind) {
    case LedgerKind.deposit:
      return 'Depósito';
    case LedgerKind.withdraw:
      return 'Saque';
    case LedgerKind.trade:
      return 'Negociação';
    case LedgerKind.fee:
      return 'Taxa';
    case LedgerKind.funding:
      return 'Funding';
    case LedgerKind.transferIn:
      return 'Transferência recebida';
    case LedgerKind.transferOut:
      return 'Transferência enviada';
    case LedgerKind.internalTransfer:
      return 'Transferência entre carteiras';
    case LedgerKind.cardPurchase:
      return 'Compra no cartão';
    case LedgerKind.cardRefund:
      return 'Estorno do cartão';
    case LedgerKind.interest:
      return 'Juros';
    case LedgerKind.bonus:
      return 'Bônus';
    case LedgerKind.settlement:
      return 'Liquidação';
    case LedgerKind.other:
      return rawType.isEmpty ? 'Movimentação' : rawType;
  }
}
