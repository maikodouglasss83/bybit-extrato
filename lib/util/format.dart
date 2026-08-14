import 'package:intl/intl.dart';

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$', decimalDigits: 2);
final _usd = NumberFormat.currency(locale: 'pt_BR', symbol: r'US$', decimalDigits: 2);
final _plain = NumberFormat('#,##0.00', 'pt_BR');
final _time = DateFormat('HH:mm', 'pt_BR');
final _dayMonth = DateFormat("d 'de' MMMM", 'pt_BR');
final _dayMonthYear = DateFormat("d 'de' MMMM 'de' y", 'pt_BR');
final _full = DateFormat("d MMM y 'às' HH:mm", 'pt_BR');
final _monthYear = DateFormat('MMMM \'de\' y', 'pt_BR');
final _monthShort = DateFormat('MMM/yy', 'pt_BR');

/// Valor monetário na moeda de exibição escolhida.
String fmtFiat(double value, {bool brl = false}) =>
    brl ? _brl.format(value) : _usd.format(value);

String fmtPlain(double value) => _plain.format(value);

/// Quantidade de cripto: casas suficientes para não sumir com valores pequenos,
/// sem arrastar zeros à direita.
String fmtCrypto(double value) {
  final abs = value.abs();
  int digits;
  if (abs == 0) {
    digits = 2;
  } else if (abs >= 1000) {
    digits = 2;
  } else if (abs >= 1) {
    digits = 4;
  } else if (abs >= 0.0001) {
    digits = 6;
  } else {
    digits = 8;
  }
  var s = NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: digits).format(value);
  if (s.contains(',')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith(',')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Quantidade com sinal explícito, como aparece no extrato.
String fmtSigned(double value) {
  final body = fmtCrypto(value.abs());
  return value < 0 ? '- $body' : '+ $body';
}

/// Moedas nacionais ganham símbolo; cripto fica com a sigla ao lado.
String fmtAmount(double value, String coin, {bool signed = true}) {
  final c = coin.toUpperCase();
  final abs = value.abs();
  final String body;
  if (c == 'BRL') {
    body = _brl.format(abs);
  } else if (c == 'USD' || c == 'USDT' || c == 'USDC') {
    body = '${_usd.format(abs)}${c == 'USD' ? '' : ' $c'}';
  } else {
    body = '${fmtCrypto(abs)} $c';
  }
  if (!signed) return body;
  return value < 0 ? '- $body' : '+ $body';
}

/// "agosto de 2026", com a primeira letra maiúscula.
String fmtMonthYear(DateTime d) {
  final s = _monthYear.format(d);
  return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// "ago/26", para eixos e comparações curtas.
String fmtMonthShort(DateTime d) => _monthShort.format(d);

/// Percentual já arredondado para exibição.
String fmtPercent(double ratio) =>
    '${(ratio * 100).toStringAsFixed(ratio >= 0.1 ? 0 : 1)}%';

/// Pontos de recompensa, com separador de milhar.
String fmtPoints(int value) =>
    NumberFormat.decimalPattern('pt_BR').format(value);

String fmtTime(DateTime d) => _time.format(d);

String fmtFullDate(DateTime d) => _full.format(d);

/// Cabeçalho dos grupos do extrato: "Hoje", "Ontem" ou a data por extenso.
String fmtDayLabel(DateTime d) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Ontem';
  return d.year == now.year ? _dayMonth.format(d) : _dayMonthYear.format(d);
}

/// Chave de agrupamento por dia.
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
