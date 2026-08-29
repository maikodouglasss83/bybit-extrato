import 'models.dart';

/// Assinatura cadastrada à mão.
///
/// Serve para o que não passa pelo cartão da Bybit — débito em outro banco,
/// cobrança anual rateada, plano dividido com alguém — e para o que ainda
/// não gerou compra nenhuma no histórico.
class ManualSubscription {
  const ManualSubscription({
    required this.id,
    required this.name,
    required this.monthlyBrl,
    this.category = '',
    this.dueDay,
    this.lastCharge,
  });

  final String id;
  final String name;

  /// Guardado em reais, como as metas do planejamento: assim o valor não se
  /// mexe quando o usuário troca a moeda da tela.
  final double monthlyBrl;

  /// Categoria de gasto. Vazio quando o usuário não escolheu nenhuma.
  final String category;

  /// Dia do mês em que costuma ser cobrada.
  final int? dueDay;

  /// Última cobrança conhecida, quando o usuário informou.
  final DateTime? lastCharge;

  ManualSubscription copyWith({
    String? name,
    double? monthlyBrl,
    String? category,
    int? dueDay,
    DateTime? lastCharge,
    bool clearDueDay = false,
    bool clearLastCharge = false,
  }) =>
      ManualSubscription(
        id: id,
        name: name ?? this.name,
        monthlyBrl: monthlyBrl ?? this.monthlyBrl,
        category: category ?? this.category,
        dueDay: clearDueDay ? null : (dueDay ?? this.dueDay),
        lastCharge: clearLastCharge ? null : (lastCharge ?? this.lastCharge),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'monthlyBrl': monthlyBrl,
        'category': category,
        if (dueDay != null) 'dueDay': dueDay,
        if (lastCharge != null)
          'lastCharge': lastCharge!.millisecondsSinceEpoch,
      };

  /// Devolve `null` para um registro quebrado, para uma linha estragada não
  /// levar a lista inteira junto.
  static ManualSubscription? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;

    final dia = int.tryParse(json['dueDay']?.toString() ?? '');
    final quando = int.tryParse(json['lastCharge']?.toString() ?? '');

    return ManualSubscription(
      id: id,
      name: name,
      monthlyBrl: double.tryParse(json['monthlyBrl']?.toString() ?? '') ?? 0,
      category: json['category']?.toString() ?? '',
      dueDay: dia != null && dia >= 1 && dia <= 31 ? dia : null,
      lastCharge: quando != null && quando > 0
          ? DateTime.fromMillisecondsSinceEpoch(quando)
          : null,
    );
  }
}

/// Uma linha da página de assinaturas.
///
/// Junta as duas origens sob a mesma forma: o que o app deduziu das compras
/// do cartão e o que o usuário cadastrou à mão.
class Subscription {
  const Subscription({
    required this.key,
    required this.name,
    required this.monthlyBrl,
    required this.manual,
    required this.cancelled,
    this.category = '',
    this.lastCharge,
    this.dueDay,
    this.chargeCount = 0,
    this.sample,
  });

  /// Identifica a assinatura nos ajustes: a chave do estabelecimento, quando
  /// vem do cartão, ou `manual:<id>` quando foi cadastrada.
  final String key;

  final String name;
  final String category;

  /// Quanto custa por mês, em reais.
  final double monthlyBrl;

  final DateTime? lastCharge;
  final int? dueDay;

  /// Quantas cobranças existem no histórico.
  final int chargeCount;

  final bool manual;

  /// Marcada como cancelada: continua na lista, riscada, mas fora da conta.
  final bool cancelled;

  /// Uma compra do estabelecimento, para o logo e para abrir o editor.
  final LedgerEntry? sample;

  bool get active => !cancelled;
}
