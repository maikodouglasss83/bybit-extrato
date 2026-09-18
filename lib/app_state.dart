import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;

import 'budget.dart';
import 'models.dart';
import 'subscriptions.dart';
import 'services/bybit_client.dart';
import 'services/cloud_sync.dart';
import 'services/credentials.dart';
import 'services/fx.dart';
import 'services/preferences.dart';
import 'util/brands.dart';
import 'util/categorizer.dart';
import 'util/format.dart';

enum LoadPhase { booting, needsSetup, loading, ready, failed }

/// Previsão de um compromisso mensal, deduzida do histórico.
class FixedForecast {
  const FixedForecast({
    required this.merchantKey,
    required this.merchant,
    required this.expectedDay,
    required this.expectedDate,
    required this.expectedAmount,
    required this.paid,
    required this.monthsSeen,
    required this.daysUntil,
    this.paidDate,
    this.confirmedDay = false,
  });

  /// Identifica o estabelecimento, para chegar às compras dele.
  final String merchantKey;

  final String merchant;

  /// Dia do mês em que costuma cair.
  final int expectedDay;
  final DateTime expectedDate;

  /// Valor já cobrado, quando pago; senão o da última vez.
  final double expectedAmount;

  final bool paid;
  final DateTime? paidDate;

  /// Em quantos meses diferentes já apareceu — mede a confiança na previsão.
  final int monthsSeen;

  /// O dia foi definido pelo usuário, e não deduzido do histórico.
  final bool confirmedDay;

  /// Dias até a data prevista. Negativo quando ela já passou.
  final int daysUntil;

  /// Passou do dia e não apareceu: vale um alerta.
  bool get late => !paid && daysUntil < 0;

  bool get dueToday => !paid && daysUntil == 0;

  bool get dueSoon => !paid && daysUntil > 0 && daysUntil <= 5;
}

/// Quanto uma categoria representou nos gastos de um período.
class CategoryTotal {
  const CategoryTotal({
    required this.label,
    required this.total,
    required this.count,
    required this.share,
    this.id,
  });

  /// Identificador da categoria principal, quando a soma é por grupo.
  final String? id;

  final String label;
  final double total;
  final int count;

  /// Fatia do gasto do período, de 0 a 1.
  final double share;
}

/// Filtros disponíveis no extrato.
enum LedgerFilter {
  all,
  card,
  uncategorized,
  incoming,
  outgoing,
  transfers,
  deposits,
  withdrawals,
  trades,
}

String ledgerFilterLabel(LedgerFilter f) {
  switch (f) {
    case LedgerFilter.all:
      return 'Tudo';
    case LedgerFilter.card:
      return 'Cartão';
    case LedgerFilter.uncategorized:
      return 'Sem categoria';
    case LedgerFilter.incoming:
      return 'Entradas';
    case LedgerFilter.outgoing:
      return 'Saídas';
    case LedgerFilter.transfers:
      return 'Transferências';
    case LedgerFilter.deposits:
      return 'Depósitos';
    case LedgerFilter.withdrawals:
      return 'Saques';
    case LedgerFilter.trades:
      return 'Negociações';
  }
}

/// Estado único do app: credenciais, saldos, extrato e preferências de exibição.
class AppState extends ChangeNotifier {
  AppState({
    CredentialsStore? store,
    FxService? fx,
    PreferencesStore? preferences,
    CloudSync? cloud,
  })  : _store = store ?? CredentialsStore(),
        _fx = fx ?? FxService(),
        _preferences = preferences ?? PreferencesStore(),
        _cloud = cloud ?? CloudSync();

  final CredentialsStore _store;
  final FxService _fx;
  final PreferencesStore _preferences;
  final CloudSync _cloud;

  CloudSync get cloud => _cloud;

  bool get cloudAvailable => _cloud.available;
  bool get cloudSignedIn => _cloud.signedIn;
  String? get cloudEmail => _cloud.userEmail;
  String? get cloudName => _cloud.userName;
  String? get cloudAvatar => _cloud.userAvatar;

  /// O usuário optou por usar sem conta. Guardado para a tela de entrada não
  /// reaparecer a cada abertura.
  bool skippedLogin = false;

  /// Mostra a tela de entrada só enquanto faz sentido oferecê-la.
  bool get needsLoginScreen =>
      cloudAvailable && !cloudSignedIn && !skippedLogin;

  Future<void> skipLogin() async {
    skippedLogin = true;
    notifyListeners();
    await _preferences.saveSkippedLogin(true);
  }

  Future<void> signInWithGoogle() async {
    await _cloud.signInWithGoogle(redirectTo: _redirectUrl);
  }

  /// Para onde o provedor devolve o usuário depois de entrar.
  String? _redirectUrl;
  set redirectUrl(String? value) => _redirectUrl = value;

  StreamSubscription<dynamic>? _authSub;

  /// Assim que a sessão aparece, os dados descem — é o que faz o login já
  /// trazer tudo pronto, sem passo extra.
  void _watchAuth() {
    _authSub?.cancel();
    _authSub = _cloud.authChanges?.listen((_) {
      if (_cloud.signedIn) {
        skippedLogin = false;
        unawaited(syncWithCloud());
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  bool cloudSyncing = false;
  String? cloudError;
  DateTime? cloudLastSync;

  BybitClient? _client;
  Credentials? _credentials;

  LoadPhase phase = LoadPhase.booting;
  String? errorMessage;

  WalletSnapshot snapshot = WalletSnapshot.empty();
  List<CoinBalance> fundingCoins = const [];
  CardRewards cardRewards = CardRewards.empty;
  final List<LedgerEntry> _entries = [];
  String? _cursor;
  int _cardPage = 1;
  bool _cardHasMore = false;
  bool _logHasMore = false;
  bool loadingMore = false;
  DateTime? lastSync;

  bool get hasMore => _logHasMore || _cardHasMore;

  Map<String, double> prices = const {};
  double? usdBrl;

  // Preferências de exibição

  /// O que o usuário escolheu. O real é o padrão: é a moeda das compras dele.
  bool _showInBrl = true;

  /// O que de fato vale na tela.
  ///
  /// Sem cotação não dá para converter, e mostrar um número em dólar com o
  /// símbolo de real seria pior do que mostrar em dólar: cai para o dólar até
  /// a cotação chegar.
  bool get showInBrl => _showInBrl && usdBrl != null;

  /// Indica que o real está escolhido mas ainda não dá para usar.
  bool get waitingForRate => _showInBrl && usdBrl == null;

  /// Define a moeda sem passar por armazenamento nem rede, para os testes.
  @visibleForTesting
  set preferBrl(bool value) => _showInBrl = value;
  bool hideBalances = false;
  LedgerFilter filter = LedgerFilter.all;
  String search = '';

  Credentials? get credentials => _credentials;
  bool get isConfigured => _client != null;

  /// Falso quando o cofre do dispositivo recusou guardar a chave — acontece
  /// quando o app é servido por HTTP sem criptografia. Aí a chave vale só
  /// enquanto a aba estiver aberta.
  bool credentialsPersisted = true;

  /// Extrato já filtrado e ordenado do mais recente para o mais antigo.
  List<LedgerEntry> get entries {
    final query = search.trim().toLowerCase();
    final list = [..._entries, ..._pendingCard].where((e) {
      if (!_matchesFilter(e)) return false;
      if (query.isEmpty) return true;
      return e.coin.toLowerCase().contains(query) ||
          (e.note?.toLowerCase().contains(query) ?? false) ||
          displayNameOf(e).toLowerCase().contains(query) ||
          categoryOf(e).toLowerCase().contains(query) ||
          (e.symbol?.toLowerCase().contains(query) ?? false) ||
          kindLabel(e.kind, e.rawType).toLowerCase().contains(query);
    }).toList();
    list.sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  bool _matchesFilter(LedgerEntry e) {
    if (filter == LedgerFilter.all) return true;
    if (filter == LedgerFilter.card) return e.isCard;
    if (filter == LedgerFilter.uncategorized) return isUncategorized(e);
    if (filter == LedgerFilter.transfers) {
      return e.kind == LedgerKind.internalTransfer;
    }
    // Transferências entre carteiras próprias não são entrada nem saída.
    if (e.neutral) return false;
    if (filter == LedgerFilter.incoming) return e.change > 0;
    if (filter == LedgerFilter.outgoing) return e.change < 0;
    if (filter == LedgerFilter.deposits) {
      return e.kind == LedgerKind.deposit || e.kind == LedgerKind.transferIn;
    }
    if (filter == LedgerFilter.withdrawals) {
      return e.kind == LedgerKind.withdraw || e.kind == LedgerKind.transferOut;
    }
    return e.kind == LedgerKind.trade || e.kind == LedgerKind.funding;
  }

  /// Converte um valor em dólar para a moeda de exibição escolhida.
  double toDisplay(double usd) => showInBrl && usdBrl != null ? usd * usdBrl! : usd;

  /// O inverso de [toDisplay]: um valor digitado na moeda da tela, em dólar.
  /// É o que deixa a meta do nível ser editada em real e continuar guardada
  /// na moeda em que a Bybit mede o nível.
  double displayToUsd(double value) =>
      showInBrl && usdBrl != null && usdBrl! > 0 ? value / usdBrl! : value;

  /// Valor em dólar de uma quantidade de determinada moeda.
  double usdValueOf(String coin, double amount) {
    final c = coin.toUpperCase();
    if (c == 'BRL') return usdBrl == null || usdBrl == 0 ? 0 : amount / usdBrl!;
    if (c == 'USD') return amount;
    final price = prices[c];
    if (price == null) return 0;
    return amount * price;
  }

  /// Quanto um montante vale na moeda escolhida para exibição.
  double displayValueOf(String coin, double amount) =>
      toDisplay(usdValueOf(coin, amount));

  /// Moedas que o usuário lê como dinheiro, e não como quantidade de cripto.
  static const _fiatLike = {'BRL', 'USD', 'USDT', 'USDC'};

  /// Texto de um valor já na moeda escolhida no seletor.
  ///
  /// Reais e stablecoins viram o valor convertido — é o que o usuário espera
  /// ao trocar para dólar. Cripto de verdade mantém a quantidade, porque
  /// "0,004 BTC" diz mais do que o equivalente em dinheiro; a conversão
  /// aparece embaixo, na linha secundária.
  String formatValue(double amount, String coin, {bool signed = true}) {
    final c = coin.toUpperCase();
    final convertivel = _fiatLike.contains(c) && (usdBrl != null || !showInBrl);

    if (!convertivel) return fmtAmount(amount, coin, signed: signed);

    final valor = displayValueOf(c, amount);
    // Sem cotação para aquela moeda o valor daria zero: melhor mostrar o
    // original do que mentir.
    if (valor == 0 && amount != 0) return fmtAmount(amount, coin, signed: signed);

    final corpo = fmtFiat(valor.abs(), brl: showInBrl);
    if (!signed) return corpo;
    return valor < 0 || amount < 0 ? '- $corpo' : '+ $corpo';
  }

  /// As metas do planejamento são guardadas em reais, que é a moeda das
  /// compras. Estes dois conversores deixam a edição acontecer na moeda que
  /// está na tela, sem o usuário ter que fazer a conta de cabeça.
  double brlToDisplay(double brl) => displayValueOf('BRL', brl);

  double displayToBrl(double value) {
    if (showInBrl || usdBrl == null) return value;
    return value * usdBrl!;
  }

  /// Símbolo da moeda em que os valores estão sendo mostrados.
  String get displayCurrencySymbol => showInBrl ? r'R$ ' : r'US$ ';

  /// Quando o valor principal já está na moeda de exibição, a linha
  /// secundária com a conversão vira repetição.
  bool showsConverted(String coin) =>
      _fiatLike.contains(coin.toUpperCase()) && (usdBrl != null || !showInBrl);

  /// Soma das moedas guardadas na carteira de fundos, em dólar.
  double get fundingUsd =>
      fundingCoins.fold<double>(0, (sum, c) => sum + c.usdValue);

  /// Patrimônio somando a carteira unificada e a de fundos.
  double get totalEquityUsd => snapshot.totalEquity + fundingUsd;

  /// Saldo que pode ser usado agora, nas duas carteiras.
  double get totalAvailableUsd =>
      snapshot.totalAvailableBalance +
      fundingCoins.fold<double>(
        0,
        (sum, c) => sum + usdValueOf(c.coin, c.availableToWithdraw),
      );

  /// Correções feitas à mão, indexadas pelo nome original do estabelecimento.
  Map<String, String> _categoryOverrides = {};
  Map<String, String> _nameOverrides = {};

  /// Lançamentos tirados das contas, por identificador. Diferente das
  /// correções acima, ocultar vale para uma transação específica: dois
  /// gastos no mesmo lugar podem ter destinos diferentes.
  ///
  /// Um lançamento oculto continua visível nas listas, riscado, para que dê
  /// para conferir e desfazer — o que ele perde é o peso nos totais.
  Set<String> _hiddenIds = {};

  bool isHidden(LedgerEntry e) => _hiddenIds.contains(e.id);

  /// Baixar os logos das marcas em vez de usar o monograma colorido.
  /// Fica desligado por padrão porque envia o domínio de cada marca a um
  /// serviço de terceiros — o resto do app só fala com a Bybit.
  bool useOnlineLogos = false;

  Future<void> toggleOnlineLogos() async {
    useOnlineLogos = !useOnlineLogos;
    notifyListeners();
    await _preferences.saveOnlineLogos(useOnlineLogos);
  }

  int get hiddenCount => _hiddenIds.length;

  /// Tira um lançamento das contas, ou devolve.
  Future<void> setHidden(LedgerEntry e, bool hidden) async {
    final novo = Set<String>.from(_hiddenIds);
    if (hidden) {
      novo.add(e.id);
    } else {
      novo.remove(e.id);
    }
    _hiddenIds = novo;
    notifyListeners();
    await _preferences.saveHiddenEntries(_hiddenIds);
    _syncPreference(_kSyncOcultos, _hiddenIds.toList());
  }

  /// Devolve todos os lançamentos ocultos às contas.
  Future<void> clearHidden() async {
    if (_hiddenIds.isEmpty) return;
    _hiddenIds = {};
    notifyListeners();
    await _preferences.saveHiddenEntries(_hiddenIds);
    _syncPreference(_kSyncOcultos, _hiddenIds.toList());
  }

  /// Chave que identifica o estabelecimento nos ajustes.
  ///
  /// Marcas conhecidas viram uma chave única, porque a Bybit escreve o mesmo
  /// lugar de formas diferentes a cada mês. Sem isso, `DM*Spotify` e
  /// `DM *Spotify` virariam dois compromissos separados na agenda — um pago,
  /// outro eternamente pendente.
  String _merchantKey(LedgerEntry e) => merchantKeyFor(e.note);

  static String merchantKeyFor(String? merchant) {
    final bruto = (merchant ?? '').trim();
    if (bruto.isEmpty) return '';

    final marca = brandFor(bruto);
    if (marca != null) return 'marca:${marca.id}';

    // Sem marca conhecida, normaliza os espaços: a Bybit alinha os nomes com
    // sequências de espaços que variam ("MP          *MELIMAIS").
    return bruto.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Traz ajustes guardados com o formato antigo de chave para o novo.
  ///
  /// Sem isto, passar a agrupar por marca faria o usuário perder tudo que já
  /// tinha personalizado.
  static Map<String, T> _migrateKeys<T>(Map<String, T> antigo) {
    final novo = <String, T>{};
    antigo.forEach((chave, valor) {
      if (chave.startsWith('marca:')) {
        novo[chave] = valor;
        return;
      }
      novo[merchantKeyFor(chave)] = valor;
    });
    novo.remove('');
    return novo;
  }

  /// Categoria válida de um lançamento: a correção do usuário vence a
  /// classificação automática.
  String categoryOf(LedgerEntry e) {
    final key = _merchantKey(e);
    if (key.isNotEmpty) {
      final override = _categoryOverrides[key];
      if (override != null) return override;
    }
    return e.category ?? SpendCategories.outros;
  }

  /// Apelidos dados a uma compra específica, pelo identificador dela.
  ///
  /// Duas compras no mesmo lugar podem ser coisas diferentes — o nome do
  /// estabelecimento não diz o que foi comprado. Por isso este apelido vence
  /// o do estabelecimento: ele é a escolha mais específica.
  Map<String, String> _entryNameOverrides = {};

  /// Nome a exibir: o apelido dado pelo usuário vence o que a Bybit mandou.
  String displayNameOf(LedgerEntry e) {
    final soDesta = _entryNameOverrides[e.id];
    if (soDesta != null && soDesta.isNotEmpty) return soDesta;

    final key = _merchantKey(e);
    if (key.isNotEmpty) {
      final override = _nameOverrides[key];
      if (override != null && override.isNotEmpty) return override;
    }
    return e.note ?? kindLabel(e.kind, e.rawType);
  }

  /// Nome que valeria sem o apelido desta compra — o do estabelecimento, ou
  /// o que veio da Bybit.
  String merchantNameOf(LedgerEntry e) {
    final key = _merchantKey(e);
    if (key.isNotEmpty) {
      final override = _nameOverrides[key];
      if (override != null && override.isNotEmpty) return override;
    }
    return e.note ?? kindLabel(e.kind, e.rawType);
  }

  /// Nome original, como veio da Bybit.
  String? originalNameOf(LedgerEntry e) => e.note;

  /// Compra que o app não conseguiu classificar e que o usuário ainda não
  /// corrigiu. "Outros" escolhido à mão é uma decisão, não uma pendência.
  bool isUncategorized(LedgerEntry e) =>
      e.kind == LedgerKind.cardPurchase &&
      !hasCustomCategory(e) &&
      categoryOf(e) == SpendCategories.outros;

  /// Quantas compras estão esperando uma categoria.
  int get uncategorizedCount =>
      cardEntries.where(isUncategorized).length;

  bool hasCustomCategory(LedgerEntry e) =>
      _categoryOverrides.containsKey(_merchantKey(e));

  bool hasCustomName(LedgerEntry e) =>
      _entryNameOverrides.containsKey(e.id) ||
      _nameOverrides.containsKey(_merchantKey(e));

  /// O apelido vale só para esta compra, e não para o estabelecimento todo.
  bool hasEntryName(LedgerEntry e) => _entryNameOverrides.containsKey(e.id);

  bool hasCustomizations(LedgerEntry e) =>
      hasCustomCategory(e) || hasCustomName(e);

  /// Quantas compras existem no mesmo estabelecimento — é o que decide se
  /// vale perguntar ao usuário onde o apelido deve valer.
  int merchantEntryCount(LedgerEntry e) {
    final key = _merchantKey(e);
    if (key.isEmpty) return 1;
    return _entries.where((o) => _merchantKey(o) == key).length;
  }

  /// Grava nome e categoria de uma compra.
  ///
  /// A categoria sempre vale para o estabelecimento inteiro: classificar é
  /// dizer que tipo de lugar é aquele. Já o nome pode valer só para aquela
  /// compra, quando `nameOnlyThis` for verdadeiro.
  ///
  /// Passar `null` mantém o valor atual; passar vazio no nome remove o apelido.
  Future<void> setEntryOverrides(
    LedgerEntry e, {
    String? name,
    String? category,
    bool nameOnlyThis = false,
  }) async {
    final key = _merchantKey(e);
    if (key.isEmpty) return;

    if (category != null) {
      _categoryOverrides = {..._categoryOverrides, key: category};
    }

    if (name != null) {
      final limpo = name.trim();
      final porCompra = Map<String, String>.from(_entryNameOverrides);
      final porEstabelecimento = Map<String, String>.from(_nameOverrides);

      if (nameOnlyThis) {
        // Apelido igual ao que já apareceria não é personalização.
        if (limpo.isEmpty || limpo == merchantNameOf(e).trim()) {
          porCompra.remove(e.id);
        } else {
          porCompra[e.id] = limpo;
        }
      } else {
        if (limpo.isEmpty || limpo == (e.note ?? '').trim()) {
          porEstabelecimento.remove(key);
        } else {
          porEstabelecimento[key] = limpo;
        }
        // Sem isto o apelido desta compra continuaria vencendo, e a mudança
        // pareceria não ter surtido efeito justo na linha que foi editada.
        porCompra.remove(e.id);
      }

      _entryNameOverrides = porCompra;
      _nameOverrides = porEstabelecimento;
    }

    notifyListeners();
    await _preferences.saveCategoryOverrides(_categoryOverrides);
    await _preferences.saveNameOverrides(_nameOverrides);
    await _preferences.saveEntryNameOverrides(_entryNameOverrides);
    _syncPreference(_kSyncCategorias, _categoryOverrides);
    _syncPreference(_kSyncNomes, _nameOverrides);
    _syncPreference(_kSyncNomesPorCompra, _entryNameOverrides);
  }

  /// Devolve o estabelecimento ao nome e à categoria automáticos, junto com
  /// o apelido que valia só para esta compra.
  Future<void> clearOverridesFor(LedgerEntry e) async {
    final key = _merchantKey(e);
    if (!_categoryOverrides.containsKey(key) &&
        !_nameOverrides.containsKey(key) &&
        !_entryNameOverrides.containsKey(e.id)) {
      return;
    }
    _categoryOverrides = Map<String, String>.from(_categoryOverrides)..remove(key);
    _nameOverrides = Map<String, String>.from(_nameOverrides)..remove(key);
    _entryNameOverrides = Map<String, String>.from(_entryNameOverrides)
      ..remove(e.id);
    notifyListeners();
    await _preferences.saveCategoryOverrides(_categoryOverrides);
    await _preferences.saveNameOverrides(_nameOverrides);
    await _preferences.saveEntryNameOverrides(_entryNameOverrides);
    _syncPreference(_kSyncCategorias, _categoryOverrides);
    _syncPreference(_kSyncNomes, _nameOverrides);
    _syncPreference(_kSyncNomesPorCompra, _entryNameOverrides);
  }

  /// Quantos estabelecimentos foram ajustados à mão, por nome ou categoria.
  int get customizedMerchantCount =>
      {..._categoryOverrides.keys, ..._nameOverrides.keys}.length;

  // ---------------------------------------------------------------------
  // Gasto fixo x variável
  // ---------------------------------------------------------------------

  /// Estabelecimentos que o usuário marcou ou desmarcou como gasto fixo.
  /// Sem marcação, vale o palpite pela categoria.
  Map<String, bool> _fixedOverrides = {};

  /// Se aquele gasto é compromisso mensal.
  ///
  /// A escolha do usuário vence; na falta dela, categorias como assinaturas,
  /// telefone e casa entram como fixas — é o que costuma chegar todo mês.
  bool isFixed(LedgerEntry e) {
    final key = _merchantKey(e);
    final escolha = _fixedOverrides[key];
    if (escolha != null) return escolha;
    return SpendCategories.fixasPorPadrao.contains(categoryOf(e));
  }

  /// Indica que o usuário decidiu isso à mão, e não o palpite automático.
  bool hasFixedOverride(LedgerEntry e) =>
      _fixedOverrides.containsKey(_merchantKey(e));

  /// Marca ou desmarca o estabelecimento como gasto fixo, valendo para todas
  /// as compras dele.
  Future<void> setFixed(LedgerEntry e, bool fixo) async {
    final key = _merchantKey(e);
    if (key.isEmpty) return;
    _fixedOverrides = {..._fixedOverrides, key: fixo};
    notifyListeners();
    await _preferences.saveFixedOverrides(_fixedOverrides);
    _syncPreference(_kSyncFixos, _fixedOverrides);
  }

  /// Volta ao palpite automático da categoria.
  Future<void> clearFixedOverride(LedgerEntry e) async {
    final key = _merchantKey(e);
    if (!_fixedOverrides.containsKey(key)) return;
    _fixedOverrides = Map<String, bool>.from(_fixedOverrides)..remove(key);
    notifyListeners();
    await _preferences.saveFixedOverrides(_fixedOverrides);
    _syncPreference(_kSyncFixos, _fixedOverrides);
  }

  /// Compras do mês separadas entre compromisso mensal e gasto do dia a dia.
  ({double fixo, double variavel}) fixedVsVariable(DateTime month) {
    var fixo = 0.0;
    var variavel = 0.0;
    for (final e in cardEntries) {
      if (e.kind != LedgerKind.cardPurchase || isHidden(e)) continue;
      if (e.time.year != month.year || e.time.month != month.month) continue;
      if (isFixed(e)) {
        fixo += e.change.abs();
      } else {
        variavel += e.change.abs();
      }
    }
    return (fixo: fixo, variavel: variavel);
  }

  /// Dia de vencimento definido à mão, por estabelecimento.
  /// Sem definição, o app deduz o dia do histórico.
  Map<String, int> _dueDayOverrides = {};

  /// Dia que o usuário fixou para aquele estabelecimento, se houver.
  int? dueDayOf(LedgerEntry e) => _dueDayOverrides[_merchantKey(e)];

  /// Fixa o dia do vencimento. Passar `null` devolve ao palpite automático.
  Future<void> setDueDay(LedgerEntry e, int? dia) async {
    final key = _merchantKey(e);
    if (key.isEmpty) return;

    final novo = Map<String, int>.from(_dueDayOverrides);
    if (dia == null || dia < 1 || dia > 31) {
      novo.remove(key);
    } else {
      novo[key] = dia;
    }
    _dueDayOverrides = novo;

    notifyListeners();
    await _preferences.saveDueDays(_dueDayOverrides);
    _syncPreference(_kSyncVencimentos, _dueDayOverrides);
  }

  /// Previsão de um compromisso no mês de referência.
  ///
  /// Sai do próprio histórico: o dia costumeiro e o valor recente de cada
  /// estabelecimento marcado como fixo.
  List<FixedForecast> fixedForecast(DateTime month) {
    // Agrupa as compras fixas pelo estabelecimento de origem — a mesma chave
    // usada nos ajustes, para o dia definido à mão bater com o grupo certo.
    final porEstabelecimento = <String, List<LedgerEntry>>{};
    for (final e in cardEntries) {
      if (e.kind != LedgerKind.cardPurchase || isHidden(e)) continue;
      if (!isFixed(e)) continue;
      porEstabelecimento.putIfAbsent(_merchantKey(e), () => []).add(e);
    }

    final agora = DateTime.now();
    final previsoes = <FixedForecast>[];

    porEstabelecimento.forEach((chave, compras) {
      compras.sort((a, b) => b.time.compareTo(a.time));

      final definidoPeloUsuario = _dueDayOverrides[chave];

      // Em quantos meses distintos apareceu. Um único mês não é padrão, é
      // coincidência — não dá para deduzir nada dali. Com o dia definido à
      // mão isso deixa de importar: a data já é conhecida.
      final meses = compras
          .map((e) => '${e.time.year}-${e.time.month}')
          .toSet();

      final doMes = compras
          .where((e) => e.time.year == month.year && e.time.month == month.month)
          .toList();

      if (definidoPeloUsuario == null && meses.length < 2 && doMes.isEmpty) {
        return;
      }

      // O dia definido manda; na falta dele, a mediana das cobranças — que
      // não se desloca por um adiantamento isolado, como a média faria.
      final int diaBase;
      if (definidoPeloUsuario != null) {
        diaBase = definidoPeloUsuario;
      } else {
        final dias = compras.map((e) => e.time.day).toList()..sort();
        diaBase = dias[dias.length ~/ 2];
      }

      // Meses têm tamanhos diferentes: dia 31 vira o último dia de fevereiro.
      final ultimoDia = DateTime(month.year, month.month + 1, 0).day;
      final diaPrevisto = diaBase > ultimoDia ? ultimoDia : diaBase;
      final dataPrevista = DateTime(month.year, month.month, diaPrevisto);

      final pago = doMes.isNotEmpty;
      final valorPrevisto = pago
          ? doMes.fold<double>(0, (s, e) => s + e.change.abs())
          : compras.first.change.abs();

      previsoes.add(FixedForecast(
        merchantKey: chave,
        merchant: merchantNameOf(compras.first),
        expectedDay: diaPrevisto,
        expectedDate: dataPrevista,
        expectedAmount: valorPrevisto,
        paid: pago,
        paidDate: pago ? doMes.first.time : null,
        monthsSeen: meses.length,
        confirmedDay: definidoPeloUsuario != null,
        daysUntil: dataPrevista
            .difference(DateTime(agora.year, agora.month, agora.day))
            .inDays,
      ));
    });

    // O que falta pagar vem primeiro, na ordem em que vence.
    previsoes.sort((a, b) {
      if (a.paid != b.paid) return a.paid ? 1 : -1;
      return a.expectedDay.compareTo(b.expectedDay);
    });
    return previsoes;
  }

  /// Todas as compras de um estabelecimento, da mais recente para a mais
  /// antiga. Junta as variações de grafia, porque a chave é a mesma.
  List<LedgerEntry> entriesOfMerchant(String merchantKey) {
    final lista = cardEntries
        .where((e) => _merchantKey(e) == merchantKey)
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return lista;
  }

  /// Quanto ainda deve cair de compromisso neste mês.
  double pendingFixedInMonth(DateTime month) => fixedForecast(month)
      .where((f) => !f.paid)
      .fold<double>(0, (sum, f) => sum + f.expectedAmount);

  /// Estabelecimentos fixos do mês, do maior para o menor — é a lista de
  /// compromissos que se repetem.
  List<MapEntry<String, double>> fixedMerchants(DateTime month) {
    final totais = <String, double>{};
    for (final e in cardEntries) {
      if (e.kind != LedgerKind.cardPurchase || isHidden(e)) continue;
      if (e.time.year != month.year || e.time.month != month.month) continue;
      if (!isFixed(e)) continue;
      final nome = merchantNameOf(e);
      totais[nome] = (totais[nome] ?? 0) + e.change.abs();
    }
    final lista = totais.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return lista;
  }

  // ---------------------------------------------------------------------
  // Assinaturas
  // ---------------------------------------------------------------------

  /// Assinaturas cadastradas à mão, para o que não passa pelo cartão.
  List<ManualSubscription> manualSubscriptions = const [];

  /// Assinaturas que o usuário marcou como canceladas, pela chave.
  /// Continuam na lista, riscadas, mas fora do total.
  Set<String> _cancelledSubscriptions = {};

  /// Chave de uma assinatura cadastrada à mão.
  static String manualSubscriptionKey(String id) => 'manual:$id';

  /// Valor de uma compra em reais — a moeda em que as assinaturas são
  /// guardadas. Compra já em real dispensa cotação, que é o caso comum.
  double brlValueOf(String coin, double amount) {
    if (coin.toUpperCase() == 'BRL') return amount;
    final taxa = usdBrl;
    if (taxa == null) return 0;
    return usdValueOf(coin, amount) * taxa;
  }

  /// Tudo o que se repete todo mês: os estabelecimentos marcados como gasto
  /// fixo e as assinaturas cadastradas à mão.
  ///
  /// O valor mensal de quem vem do cartão é o da cobrança mais recente — é o
  /// que a assinatura custa hoje, e não a média de um preço que já subiu.
  List<Subscription> subscriptions() {
    final porEstabelecimento = <String, List<LedgerEntry>>{};
    for (final e in cardEntries) {
      if (e.kind != LedgerKind.cardPurchase || isHidden(e)) continue;
      if (!isFixed(e)) continue;
      porEstabelecimento.putIfAbsent(_merchantKey(e), () => []).add(e);
    }

    final lista = <Subscription>[];

    porEstabelecimento.forEach((chave, compras) {
      compras.sort((a, b) => b.time.compareTo(a.time));
      final ultima = compras.first;
      lista.add(Subscription(
        key: chave,
        name: merchantNameOf(ultima),
        category: categoryOf(ultima),
        monthlyBrl: brlValueOf(ultima.coin, ultima.change.abs()),
        lastCharge: ultima.time,
        dueDay: _dueDayOverrides[chave],
        chargeCount: compras.length,
        manual: false,
        cancelled: _cancelledSubscriptions.contains(chave),
        sample: ultima,
      ));
    });

    for (final m in manualSubscriptions) {
      final chave = manualSubscriptionKey(m.id);
      lista.add(Subscription(
        key: chave,
        name: m.name,
        category: m.category,
        monthlyBrl: m.monthlyBrl,
        lastCharge: m.lastCharge,
        dueDay: m.dueDay,
        manual: true,
        cancelled: _cancelledSubscriptions.contains(chave),
      ));
    }

    // Pelo dia do mês em que vence, do dia 1 ao 31, como num calendário de
    // contas — as canceladas também, no dia delas. Sem dia conhecido vão para
    // o fim. No mesmo dia, a mais cara vem antes.
    lista.sort((a, b) {
      final da = a.diaDoVencimento;
      final db = b.diaDoVencimento;
      if (da != null && db != null) {
        if (da != db) return da.compareTo(db);
      } else if (da != null || db != null) {
        return da != null ? -1 : 1;
      }
      final peso = b.monthlyBrl.compareTo(a.monthlyBrl);
      if (peso != 0) return peso;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return lista;
  }

  /// Quanto as assinaturas ativas custam por mês, em reais.
  double get subscriptionsMonthlyBrl => subscriptions()
      .where((s) => s.active)
      .fold<double>(0, (soma, s) => soma + s.monthlyBrl);

  int get activeSubscriptionCount =>
      subscriptions().where((s) => s.active).length;

  /// Cadastra uma assinatura que não veio do cartão.
  Future<void> addManualSubscription({
    required String name,
    required double monthlyBrl,
    String category = '',
    int? dueDay,
    DateTime? lastCharge,
  }) async {
    final nome = name.trim();
    if (nome.isEmpty) return;

    final nova = ManualSubscription(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: nome,
      monthlyBrl: monthlyBrl,
      category: category,
      dueDay: dueDay,
      lastCharge: lastCharge,
    );
    manualSubscriptions = [...manualSubscriptions, nova];
    await _persistSubscriptions();
  }

  Future<void> updateManualSubscription(
    String id, {
    String? name,
    double? monthlyBrl,
    String? category,
    int? dueDay,
    bool clearDueDay = false,
  }) async {
    manualSubscriptions = manualSubscriptions
        .map((m) => m.id == id
            ? m.copyWith(
                name: name?.trim(),
                monthlyBrl: monthlyBrl,
                category: category,
                dueDay: dueDay,
                clearDueDay: clearDueDay,
              )
            : m)
        .toList();
    await _persistSubscriptions();
  }

  Future<void> removeManualSubscription(String id) async {
    manualSubscriptions =
        manualSubscriptions.where((m) => m.id != id).toList();
    _cancelledSubscriptions = {..._cancelledSubscriptions}
      ..remove(manualSubscriptionKey(id));
    await _persistSubscriptions();
  }

  /// Marca a assinatura como cancelada, ou a traz de volta.
  ///
  /// Isto é anotação: quem cancela de verdade é o banco ou o serviço. Serve
  /// para o total do mês parar de contar o que não vai mais ser cobrado.
  Future<void> setSubscriptionCancelled(String key, bool cancelada) async {
    if (key.isEmpty) return;
    final novo = {..._cancelledSubscriptions};
    if (cancelada) {
      novo.add(key);
    } else {
      novo.remove(key);
    }
    _cancelledSubscriptions = novo;
    await _persistSubscriptions();
  }

  bool isSubscriptionCancelled(String key) =>
      _cancelledSubscriptions.contains(key);

  /// Tira a assinatura da lista de vez.
  ///
  /// A cadastrada à mão é apagada; a que veio do cartão volta a ser gasto
  /// variável, e as compras dela continuam no extrato.
  Future<void> removeSubscription(Subscription s) async {
    if (s.manual) {
      await removeManualSubscription(s.key.replaceFirst('manual:', ''));
      return;
    }
    final compra = s.sample;
    if (compra != null) await setFixed(compra, false);
  }

  Future<void> _persistSubscriptions() async {
    notifyListeners();
    await _preferences.saveManualSubscriptions(manualSubscriptions);
    await _preferences.saveCancelledSubscriptions(_cancelledSubscriptions);
    _syncPreference(
      _kSyncAssinaturas,
      manualSubscriptions.map((m) => m.toJson()).toList(),
    );
    _syncPreference(_kSyncAssinaturasCanceladas, _cancelledSubscriptions.toList());
  }

  /// Total gasto em uma categoria dentro de um período.
  /// Lançamentos ocultos nunca entram na conta.
  List<CategoryTotal> categoryBreakdown(DateTime month) {
    final compras = cardEntriesForMonth(month)
        .where((e) => e.kind == LedgerKind.cardPurchase && !isHidden(e))
        .toList();

    final totais = <String, double>{};
    final contagem = <String, int>{};
    for (final e in compras) {
      final chave = categoryOf(e);
      totais[chave] = (totais[chave] ?? 0) + e.change.abs();
      contagem[chave] = (contagem[chave] ?? 0) + 1;
    }

    final soma = totais.values.fold<double>(0, (a, b) => a + b);
    final lista = totais.entries
        .map((e) => CategoryTotal(
              label: e.key,
              total: e.value,
              count: contagem[e.key] ?? 0,
              share: soma == 0 ? 0 : e.value / soma,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return lista;
  }

  /// Gasto do mês somado por categoria principal do planejamento.
  ///
  /// É a visão de primeiro nível da tela de gastos: as subcategorias somam
  /// dentro da principal em vez de disputarem espaço na mesma lista.
  List<CategoryTotal> mainCategoryBreakdown(DateTime month) {
    final compras = cardEntriesForMonth(month)
        .where((e) => e.kind == LedgerKind.cardPurchase && !isHidden(e));

    final totais = <String, double>{};
    final contagem = <String, int>{};
    final rotulos = <String, String>{};

    for (final e in compras) {
      final principal = mainCategoryOf(categoryOf(e));
      final id = principal?.id ?? kUncategorizedId;
      rotulos[id] = principal?.name ?? 'Sem categoria';
      totais[id] = (totais[id] ?? 0) + e.change.abs();
      contagem[id] = (contagem[id] ?? 0) + 1;
    }

    final soma = totais.values.fold<double>(0, (a, b) => a + b);
    final lista = totais.entries
        .map((e) => CategoryTotal(
              id: e.key,
              label: rotulos[e.key] ?? e.key,
              total: e.value,
              count: contagem[e.key] ?? 0,
              share: soma == 0 ? 0 : e.value / soma,
            ))
        .toList()
      ..sort((a, b) {
        // O resto vai para o fim, como no planejamento.
        final aResto = a.id == kUncategorizedId;
        final bResto = b.id == kUncategorizedId;
        if (aResto != bResto) return aResto ? 1 : -1;
        return b.total.compareTo(a.total);
      });
    return lista;
  }

  /// Gasto por subcategoria dentro de uma principal.
  ///
  /// Agrupa pela subcategoria do planejamento, e não pela categoria de
  /// gasto: uma subcategoria pode receber várias categorias — e também as
  /// compras marcadas com o próprio nome — e tudo isso é a mesma linha.
  List<CategoryTotal> subcategoryBreakdown(DateTime month, String mainId) {
    final compras = cardEntriesForMonth(month).where((e) =>
        e.kind == LedgerKind.cardPurchase &&
        !isHidden(e) &&
        (mainCategoryOf(categoryOf(e))?.id ?? kUncategorizedId) == mainId);

    final totais = <String, double>{};
    final contagem = <String, int>{};
    final rotulos = <String, String>{};

    for (final e in compras) {
      final categoria = categoryOf(e);
      final no = nodeForCategory(categoria);
      // Sem nó, o gasto está solto em "Sem categoria": ele mesmo é o grupo.
      final chave = no?.id ?? '$_prefixoSolto$categoria';
      rotulos[chave] = no?.name ?? categoria;
      totais[chave] = (totais[chave] ?? 0) + e.change.abs();
      contagem[chave] = (contagem[chave] ?? 0) + 1;
    }

    final soma = totais.values.fold<double>(0, (a, b) => a + b);
    final lista = totais.entries
        .map((e) => CategoryTotal(
              id: e.key,
              label: rotulos[e.key] ?? e.key,
              total: e.value,
              count: contagem[e.key] ?? 0,
              share: soma == 0 ? 0 : e.value / soma,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return lista;
  }

  /// Marca as chaves que não vêm de um nó do planejamento.
  static const _prefixoSolto = 'categoria:';

  /// Compras que formam uma linha de [subcategoryBreakdown].
  List<LedgerEntry> purchasesOfSubcategory(DateTime month, String chave) {
    final semNo = chave.startsWith(_prefixoSolto);
    final categoriaSolta =
        semNo ? chave.substring(_prefixoSolto.length) : null;
    final no = semNo ? null : budgetNodeById(chave);

    final lista = cardEntriesForMonth(month).where((e) {
      if (e.kind != LedgerKind.cardPurchase || isHidden(e)) return false;
      final categoria = categoryOf(e);
      return semNo
          ? categoria == categoriaSolta
          : (no?.sources.contains(categoria) ?? false);
    }).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return lista;
  }
  /// Compras de uma categoria dentro do mês.
  List<LedgerEntry> purchasesOfCategory(DateTime month, String categoria) {
    final lista = cardEntriesForMonth(month)
        .where((e) =>
            e.kind == LedgerKind.cardPurchase &&
            !isHidden(e) &&
            categoryOf(e) == categoria)
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return lista;
  }

  /// Compras do cartão dentro do mês informado, incluindo as ocultas — que
  /// aparecem riscadas nas listas e ficam de fora dos totais.
  List<LedgerEntry> cardEntriesForMonth(DateTime month) => cardEntries
      .where((e) => e.time.year == month.year && e.time.month == month.month)
      .toList();

  /// Quanto foi gasto no cartão no mês informado, sem os ocultos.
  double cardSpentInMonth(DateTime month) => cardEntries
      .where((e) =>
          e.time.year == month.year &&
          e.time.month == month.month &&
          e.kind == LedgerKind.cardPurchase &&
          !isHidden(e))
      .fold<double>(0, (sum, e) => sum + e.change.abs());

  // ---------------------------------------------------------------------
  // Planejamento financeiro
  // ---------------------------------------------------------------------

  /// Categorias e subcategorias do planejamento, com as metas.
  List<BudgetNode> budgetNodes = defaultBudgetTree();

  List<BudgetNode> get mainBudgetNodes =>
      budgetNodes.where((n) => n.isMain).toList();

  List<BudgetNode> childrenOf(String parentId) =>
      budgetNodes.where((n) => n.parentId == parentId).toList();

  /// Categorias de gasto que já estão ligadas a algum nó.
  Set<String> get _mappedSources =>
      budgetNodes.expand((n) => n.sources).toSet();

  /// Todas as categorias que o usuário pode escolher numa compra.
  ///
  /// Junta as que o app reconhece sozinho com as que ele criou no
  /// planejamento — sem isso, uma subcategoria nova não teria como receber
  /// gasto nenhum a partir do extrato.
  List<String> get availableCategories {
    final personalizadas = budgetNodes
        .where((n) => !n.builtIn)
        .map((n) => n.name)
        .where((nome) => !SpendCategories.all.contains(nome))
        .toList()
      ..sort();

    return [...SpendCategories.all, ...personalizadas];
  }

  /// Indica que a categoria foi criada pelo usuário no planejamento.
  bool isCustomCategory(String categoria) =>
      !SpendCategories.all.contains(categoria);

  /// Categorias principais que podem ser escolhidas numa compra.
  ///
  /// "Sem categoria" fica de fora: ela é o resto do planejamento, não uma
  /// escolha — quem não quer classificar usa "Outros".
  List<BudgetNode> get selectableMainCategories =>
      mainBudgetNodes.where((n) => n.id != kUncategorizedId).toList();

  /// O valor de categoria que um nó representa.
  ///
  /// Nós padrão apontam para a categoria que o app deduz sozinho; os criados
  /// pelo usuário usam o próprio nome.
  String categoryValueOf(BudgetNode node) =>
      node.sources.isNotEmpty ? node.sources.first : node.name;

  /// Nome que aparece na tela para um valor de categoria — o rótulo do nó,
  /// quando ele existir, que costuma ser mais descritivo.
  String categoryLabelOf(String categoria) {
    for (final n in budgetNodes) {
      if (n.sources.contains(categoria)) return n.name;
    }
    return categoria;
  }

  /// O nó do planejamento que recebe aquele valor de categoria.
  BudgetNode? nodeForCategory(String categoria) =>
      budgetNodes.where((n) => n.sources.contains(categoria)).firstOrNull;

  BudgetNode? budgetNodeById(String id) =>
      budgetNodes.where((n) => n.id == id).firstOrNull;

  /// Categoria principal onde aquele valor de categoria está pendurado.
  BudgetNode? mainCategoryOf(String categoria) {
    for (final n in budgetNodes) {
      if (!n.sources.contains(categoria)) continue;
      if (n.isMain) return n;
      return budgetNodes.where((m) => m.id == n.parentId).firstOrNull;
    }
    return null;
  }

  /// Opções de segundo nível de uma categoria principal.
  ///
  /// Se ela não tiver subcategorias, ela mesma vira a opção — assim nenhuma
  /// principal fica sem caminho para ser escolhida.
  List<BudgetNode> subcategoriesFor(BudgetNode main) {
    final filhos = childrenOf(main.id);
    if (filhos.isEmpty) return [main];
    // Todas aparecem, inclusive a que ficou sem categoria de gasto: ao ser
    // escolhida, [garantirCategoriaPropria] dá a ela uma, e a compra cai nela.
    return filhos;
  }

  /// O valor de categoria que faz uma compra cair exatamente neste nó.
  ///
  /// Nó sem categoria de gasto — porque outra subcategoria levou a dele —
  /// devolveria o próprio nome, e o nome pode ser justamente o que a outra
  /// levou: a compra iria parar lá. Aqui ele ganha uma categoria só dele: o
  /// nome, se ninguém o usa; senão o nome com a principal ("Assinaturas ·
  /// Lazer"). Quem levou a categoria original continua com ela.
  Future<String> garantirCategoriaPropria(BudgetNode node) async {
    if (node.sources.isNotEmpty) return node.sources.first;

    bool livre(String valor) {
      final chave = valor.trim().toLowerCase();
      return !budgetNodes
          .any((n) => n.sources.any((s) => s.trim().toLowerCase() == chave));
    }

    final pai = node.parentId == null ? null : budgetNodeById(node.parentId!);
    final candidatos = [
      node.name,
      if (pai != null) '${node.name} · ${pai.name}',
      '${node.name} · ${node.id}',
    ];
    final valor = candidatos.firstWhere(livre, orElse: () => candidatos.last);

    budgetNodes = [
      for (final n in budgetNodes)
        n.id == node.id ? n.copyWith(sources: [valor]) : n,
    ];
    await _persistBudget();
    return valor;
  }

  /// Gasto do mês que cai direto neste nó, sem contar as subcategorias.
  double _ownSpent(BudgetNode node, DateTime month) {
    final compras = cardEntriesForMonth(month)
        .where((e) => e.kind == LedgerKind.cardPurchase && !isHidden(e));

    if (node.id == kUncategorizedId) {
      // Recolhe tudo que não foi ligado a nenhuma categoria do planejamento.
      final mapeadas = _mappedSources;
      return compras
          .where((e) => !mapeadas.contains(categoryOf(e)))
          .fold<double>(0, (sum, e) => sum + e.change.abs());
    }

    if (node.sources.isEmpty) return 0;
    return compras
        .where((e) => node.sources.contains(categoryOf(e)))
        .fold<double>(0, (sum, e) => sum + e.change.abs());
  }

  /// Meta que vale para um grupo: a própria, quando definida; senão a soma
  /// das metas das subcategorias.
  double effectiveBudget(BudgetNode node) {
    if (node.budget > 0) return node.budget;
    return childrenOf(node.id).fold<double>(0, (sum, c) => sum + c.budget);
  }

  /// Monta o planejamento do mês, com gasto e meta de cada categoria.
  List<BudgetLine> budgetLines(DateTime month) {
    final linhas = mainBudgetNodes.map((main) {
      final filhos = childrenOf(main.id)
          .map((c) => BudgetLine(
                node: c,
                spent: _ownSpent(c, month),
                budget: c.budget,
                children: const [],
              ))
          .toList()
        ..sort((a, b) => b.spent.compareTo(a.spent));

      final gastoTotal =
          _ownSpent(main, month) + filhos.fold<double>(0, (s, f) => s + f.spent);

      return BudgetLine(
        node: main,
        spent: gastoTotal,
        budget: effectiveBudget(main),
        children: filhos,
      );
    }).toList();

    // Quem tem meta ou gasto aparece primeiro; o resto vai para o fim.
    // "Sem categoria" fica sempre por último: é o resto, não uma escolha.
    linhas.sort((a, b) {
      final aResto = a.node.id == kUncategorizedId;
      final bResto = b.node.id == kUncategorizedId;
      if (aResto != bResto) return aResto ? 1 : -1;

      final peso = b.spent.compareTo(a.spent);
      if (peso != 0) return peso;
      return b.budget.compareTo(a.budget);
    });
    return linhas;
  }

  /// Soma das metas das categorias principais.
  double budgetTotal(DateTime month) =>
      budgetLines(month).fold<double>(0, (sum, l) => sum + l.budget);

  /// Total gasto no mês dentro do planejamento.
  double budgetSpentTotal(DateTime month) =>
      budgetLines(month).fold<double>(0, (sum, l) => sum + l.spent);

  /// Quanto ainda cabe gastar no mês. Negativo quando estourou a meta.
  double budgetRemaining(DateTime month) =>
      budgetTotal(month) - budgetSpentTotal(month);

  Future<void> _persistBudget() async {
    notifyListeners();
    await _preferences.saveBudgetTree(budgetNodes);
    _marcarPlanejamentoPendente(true);
    _enviarPlanejamento();
  }

  /// O planejamento daqui ainda não chegou à nuvem.
  bool _planejamentoPendente = false;

  /// Conta as mudanças do planejamento, para um envio que termina atrasado
  /// não dar por enviada uma mudança mais nova que ele não levou.
  int _versaoDoPlanejamento = 0;

  void _marcarPlanejamentoPendente(bool pendente) {
    if (pendente) _versaoDoPlanejamento++;
    if (_planejamentoPendente == pendente) return;
    _planejamentoPendente = pendente;
    _preferences.saveBudgetPending(pendente);
  }

  /// Manda a árvore para a nuvem e só tira a marca de pendente se deu certo.
  Future<void> _enviarPlanejamento() async {
    if (!_cloud.available || !_cloud.signedIn) return;
    final versao = _versaoDoPlanejamento;
    try {
      await _cloud.pushPreference(
        _kSyncPlanejamento,
        budgetNodes.map((n) => n.toJson()).toList(),
      );
      if (versao == _versaoDoPlanejamento) _marcarPlanejamentoPendente(false);
    } catch (_) {
      // Continua pendente: a próxima sincronização completa reenvia, e até lá
      // a árvore da nuvem não substitui esta.
    }
  }

  /// Quanto ainda cabe na meta de uma subcategoria, em reais.
  ///
  /// É o que sobra da meta da principal depois das outras subcategorias.
  /// Devolve `null` quando não há teto — principal sem meta definida, ou o
  /// próprio nó sendo uma principal.
  double? budgetHeadroomFor(String nodeId) {
    final node = budgetNodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null || node.isMain) return null;

    final pai = budgetNodes.where((n) => n.id == node.parentId).firstOrNull;
    if (pai == null || pai.budget <= 0) return null;

    final outras = childrenOf(pai.id)
        .where((c) => c.id != nodeId)
        .fold<double>(0, (soma, c) => soma + c.budget);

    final sobra = pai.budget - outras;
    return sobra < 0 ? 0 : sobra;
  }

  /// Define a meta mensal de uma categoria ou subcategoria, em reais.
  ///
  /// Devolve uma mensagem quando a meta não cabe na da categoria principal —
  /// somar subcategorias além do teto do grupo tornaria o planejamento
  /// incoerente consigo mesmo.
  Future<String?> setBudget(String nodeId, double value) async {
    final valor = value < 0 ? 0.0 : value;

    final teto = budgetHeadroomFor(nodeId);
    if (teto != null && valor > teto) {
      final pai = budgetNodes
          .where((n) => n.id ==
              budgetNodes.firstWhere((x) => x.id == nodeId).parentId)
          .firstOrNull;
      return 'Só cabem ${fmtFiat(brlToDisplay(teto), brl: showInBrl)} aqui: '
          'o restante da meta de ${pai?.name ?? 'grupo'} já está distribuído '
          'nas outras subcategorias.';
    }

    budgetNodes = budgetNodes
        .map((n) => n.id == nodeId ? n.copyWith(budget: valor) : n)
        .toList();
    await _persistBudget();
    return null;
  }

  Future<void> renameBudgetNode(String nodeId, String name) async {
    final limpo = name.trim();
    if (limpo.isEmpty) return;

    final anterior = budgetNodes.where((n) => n.id == nodeId).firstOrNull;
    if (anterior == null || anterior.name == limpo) return;

    budgetNodes = budgetNodes.map((n) {
      if (n.id != nodeId) return n;
      final origens = n.sources.map((s) => s == n.name ? limpo : s).toList();
      return n.copyWith(name: limpo, sources: origens);
    }).toList();

    // As compras marcadas com o nome antigo passam a levar o novo. Sem isto
    // elas ficariam apontando para uma categoria que não existe mais, e o
    // dinheiro sumiria do planejamento.
    final renomeadas = <String, String>{};
    var mudou = false;
    _categoryOverrides.forEach((chave, categoria) {
      if (categoria == anterior.name) {
        renomeadas[chave] = limpo;
        mudou = true;
      } else {
        renomeadas[chave] = categoria;
      }
    });

    if (mudou) {
      _categoryOverrides = renomeadas;
      await _preferences.saveCategoryOverrides(_categoryOverrides);
      _syncPreference(_kSyncCategorias, _categoryOverrides);
    }

    await _persistBudget();
  }

  /// Cria uma categoria principal ou uma subcategoria de [parentId].
  ///
  /// Devolve o motivo quando não dá para criar, ou nulo quando criou.
  Future<String?> addBudgetNode({
    required String name,
    String? parentId,
    double budget = 0,
    List<String> sources = const [],
  }) async {
    final limpo = name.trim();
    if (limpo.isEmpty) return 'Dê um nome para a categoria.';

    // O nome vira o valor de categoria que as compras recebem. Dois nós com
    // o mesmo nome disputariam as mesmas compras, e uma delas nunca receberia
    // nada — mesmo aparecendo no seletor.
    final repetido = limpo.toLowerCase();
    final jaExiste = budgetNodes.any((n) =>
        n.name.trim().toLowerCase() == repetido ||
        n.sources.any((s) => s.toLowerCase() == repetido));
    if (jaExiste) {
      return 'Já existe uma categoria chamada "$limpo". Escolha outro nome.';
    }

    final id = 'user_${DateTime.now().microsecondsSinceEpoch}';
    final (arvore, levadas) = _claimSources(budgetNodes, sources);

    budgetNodes = [
      ...arvore,
      BudgetNode(
        id: id,
        name: limpo,
        parentId: parentId,
        budget: budget,
        // O próprio nome entra como origem: é o que permite marcar uma compra
        // com esta categoria no extrato e ver o valor cair aqui.
        sources: <String>{limpo, ...levadas}.toList(),
      ),
    ];
    await _persistBudget();
    return null;
  }

  /// Tira de outros nós as categorias de gasto pedidas — menos a última de
  /// cada nó.
  ///
  /// Uma categoria alimenta um nó só, senão o mesmo dinheiro seria contado
  /// duas vezes. Mas levar a única categoria de um nó o deixaria vazio: na
  /// tela e no seletor, sem conseguir receber gasto nenhum. Essa fica onde
  /// está. Devolve a árvore resultante e as categorias que puderam ser levadas.
  (List<BudgetNode>, List<String>) _claimSources(
    List<BudgetNode> nodes,
    List<String> pedidas,
  ) {
    var arvore = nodes;
    final levadas = <String>[];

    for (final origem in pedidas) {
      final dono = arvore.where((n) => n.sources.contains(origem)).firstOrNull;
      if (dono != null && _ficariaVazio(dono)) continue;

      if (dono != null) {
        arvore = arvore
            .map((n) => n.id == dono.id
                ? n.copyWith(
                    sources: n.sources.where((s) => s != origem).toList(),
                  )
                : n)
            .toList();
      }
      levadas.add(origem);
    }

    return (arvore, levadas);
  }

  /// Tirar a última categoria deste nó o deixaria como destino que não recebe
  /// nada. Vale para subcategoria e para principal sem subcategorias — a
  /// principal que tem filhas continua somando o gasto delas.
  bool _ficariaVazio(BudgetNode dono) =>
      dono.sources.length < 2 &&
      (!dono.isMain || childrenOf(dono.id).isEmpty);

  /// Categorias de gasto que não podem ser levadas para um nó novo, com o
  /// nome de quem as segura: tirar deixaria aquele nó vazio.
  Map<String, String> get lockedSources => {
        for (final n in budgetNodes)
          if (n.sources.isNotEmpty && _ficariaVazio(n)) n.sources.first: n.name,
      };

  /// Tira as categorias de gasto informadas de todos os nós.
  List<BudgetNode> _withoutSources(List<BudgetNode> nodes, List<String> sources) {
    if (sources.isEmpty) return nodes;
    return nodes.map((n) {
      if (!n.sources.any(sources.contains)) return n;
      return n.copyWith(
        sources: n.sources.where((s) => !sources.contains(s)).toList(),
      );
    }).toList();
  }

  /// Remove uma categoria do planejamento.
  ///
  /// Subcategorias podem ser apagadas mesmo sendo padrão — os gastos delas
  /// sobem para a categoria pai, então nada some do planejamento. Já as
  /// categorias principais padrão ficam protegidas: apagá-las derrubaria a
  /// estrutura inteira.
  Future<void> removeBudgetNode(String nodeId) async {
    final node = budgetNodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return;
    if (node.isMain && node.builtIn) return;

    // O que ela recebia passa a cair direto na principal.
    if (!node.isMain && node.sources.isNotEmpty) {
      budgetNodes = budgetNodes.map((n) {
        if (n.id != node.parentId) return n;
        return n.copyWith(sources: {...n.sources, ...node.sources}.toList());
      }).toList();
    }

    budgetNodes = budgetNodes
        .where((n) => n.id != nodeId && n.parentId != nodeId)
        .toList();
    await _persistBudget();
  }

  bool canRemoveBudgetNode(BudgetNode node) => !(node.isMain && node.builtIn);

  /// Liga ou desliga uma categoria de gasto de um nó do planejamento. Uma
  /// categoria só alimenta um nó por vez, para nada ser contado duas vezes.
  Future<void> setBudgetSources(String nodeId, List<String> sources) async {
    budgetNodes = _withoutSources(budgetNodes, sources)
        .map((n) => n.id == nodeId ? n.copyWith(sources: sources) : n)
        .toList();
    await _persistBudget();
  }

  /// Volta o planejamento à estrutura padrão.
  Future<void> resetBudgetTree() async {
    budgetNodes = defaultBudgetTree();
    await _persistBudget();
  }

  /// Gasto mensal, em dólar, exigido para manter o nível do cartão.
  /// Padrão de US$ 500 (nível Beta, 2% de cashback), editável porque a Bybit
  /// não devolve essa régua pela API e pode mudá-la.
  static const defaultCardGoalUsd = 500.0;
  double cardGoalUsd = defaultCardGoalUsd;

  Future<void> setCardGoal(double value) async {
    if (value <= 0) return;
    cardGoalUsd = value;
    notifyListeners();
    await _preferences.saveCardGoal(value);
    _syncPreference(_kSyncMetaCartao, value);
  }

  /// Gasto do mês no cartão convertido para dólar, que é a moeda da régua.
  double cardSpentUsdInMonth(DateTime month) => cardEntries
      .where((e) =>
          e.time.year == month.year &&
          e.time.month == month.month &&
          e.kind == LedgerKind.cardPurchase &&
          !isHidden(e))
      .fold<double>(0, (sum, e) => sum + usdValueOf(e.coin, e.change.abs()));

  double get cardSpentUsdThisMonth {
    final agora = DateTime.now();
    return cardSpentUsdInMonth(DateTime(agora.year, agora.month));
  }

  /// Quanto ainda falta para bater a meta do mês, em dólar. Zero se já bateu.
  double get cardGoalRemainingUsd {
    final falta = cardGoalUsd - cardSpentUsdThisMonth;
    return falta <= 0 ? 0 : falta;
  }

  double get cardGoalProgress {
    if (cardGoalUsd <= 0) return 0;
    return (cardSpentUsdThisMonth / cardGoalUsd).clamp(0.0, 1.0);
  }

  bool get cardGoalReached => cardSpentUsdThisMonth >= cardGoalUsd;

  /// Dias que ainda restam no mês para alcançar a meta.
  int get daysLeftInMonth {
    final agora = DateTime.now();
    final ultimoDia = DateTime(agora.year, agora.month + 1, 0).day;
    return ultimoDia - agora.day + 1;
  }

  /// Período que o gráfico de evolução mostra, em meses. Zero é o histórico
  /// inteiro.
  int monthlyRange = 6;

  static const monthlyRangeOptions = <int, String>{
    1: '1 mês',
    3: '3 meses',
    6: '6 meses',
    12: '1 ano',
    0: 'Tudo',
  };

  String get monthlyRangeLabel => monthlyRangeOptions[monthlyRange] ?? '6 meses';

  void setMonthlyRange(int months) {
    monthlyRange = months;
    notifyListeners();
  }

  /// Gasto do cartão mês a mês, do mais antigo para o mais recente.
  /// É o que sustenta o gráfico de evolução: a conta unificada não devolve
  /// saldo corrente, mas o histórico de compras cobre vários meses.
  ///
  /// [months] igual a zero traz todos os meses disponíveis.
  List<MapEntry<DateTime, double>> monthlySpending({int months = 6}) {
    final compras = cardEntries
        .where((e) => e.kind == LedgerKind.cardPurchase && !isHidden(e));
    if (compras.isEmpty) return const [];

    final totais = <String, double>{};
    final chaves = <String, DateTime>{};
    for (final e in compras) {
      final mes = DateTime(e.time.year, e.time.month);
      final chave = '${mes.year}-${mes.month}';
      totais[chave] = (totais[chave] ?? 0) + e.change.abs();
      chaves[chave] = mes;
    }

    final ordenados = chaves.values.toList()..sort((a, b) => a.compareTo(b));
    final recorte = months > 0 && ordenados.length > months
        ? ordenados.sublist(ordenados.length - months)
        : ordenados;

    return [
      for (final mes in recorte)
        MapEntry(mes, totais['${mes.year}-${mes.month}'] ?? 0),
    ];
  }

  /// Quantos lançamentos daquele mês estão fora das contas.
  int hiddenCountInMonth(DateTime month) => cardEntries
      .where((e) =>
          e.time.year == month.year &&
          e.time.month == month.month &&
          isHidden(e))
      .length;

  /// Meses que já têm compras carregadas, do mais recente para o mais antigo.
  List<DateTime> get monthsWithCardData {
    final chaves = <String, DateTime>{};
    for (final e in cardEntries) {
      final m = DateTime(e.time.year, e.time.month);
      chaves['${m.year}-${m.month}'] = m;
    }
    final lista = chaves.values.toList()..sort((a, b) => b.compareTo(a));
    return lista;
  }

  /// Mês em foco na tela de gastos.
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  void selectMonth(DateTime month) {
    selectedMonth = DateTime(month.year, month.month);
    notifyListeners();
  }

  void shiftMonth(int delta) {
    final novo = DateTime(selectedMonth.year, selectedMonth.month + delta);
    final agora = DateTime.now();
    if (novo.isAfter(DateTime(agora.year, agora.month))) return;
    selectedMonth = novo;
    notifyListeners();
  }

  bool get canGoToNextMonth {
    final agora = DateTime(DateTime.now().year, DateTime.now().month);
    return selectedMonth.isBefore(agora);
  }

  /// Compras do cartão já carregadas, da mais recente para a mais antiga.
  List<LedgerEntry> get cardEntries {
    // As pendentes entram em tudo o que soma gasto: o dinheiro já saiu do
    // limite no momento em que o cartão passou.
    final list = [..._entries.where((e) => e.isCard), ..._pendingCard]
      ..sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  // ---------------------------------------------------------------------
  // Compras pendentes do cartão
  // ---------------------------------------------------------------------

  /// Autorizações que o estabelecimento ainda não confirmou.
  ///
  /// Ficam fora de [_entries] de propósito: não entram no histórico guardado
  /// nem na nuvem, e a cada atualização a lista é trocada inteira pelo que a
  /// Bybit disser que continua pendente.
  List<LedgerEntry> _pendingCard = const [];

  /// Pendentes que já saíram da lista levando um ajuste só delas — um nome
  /// próprio ou a marcação de oculta. Esperam a liquidação chegar para
  /// entregar o ajuste a ela, e não aparecem em lugar nenhum.
  List<LedgerEntry> _pendingAguardando = const [];

  /// Hora da compra de cada liquidação, pelo identificador dela.
  ///
  /// A liquidação chega com a hora em que o estabelecimento confirmou, que
  /// pode cair no dia seguinte — ou no mês seguinte. A hora certa é a da
  /// autorização, lembrada quando as duas são reconhecidas como a mesma compra.
  Map<String, int> _datasDaCompra = {};

  /// Tempo máximo entre autorizar e liquidar. Passou disso, a compra foi
  /// cancelada ou estornada, e não há mais o que esperar.
  static const _prazoDeLiquidacao = Duration(days: 15);

  int get pendingCardCount => _pendingCard.length;

  /// Troca as pendentes pelas que acabaram de chegar.
  ///
  /// Na Bybit a autorização e a liquidação têm identificadores diferentes,
  /// então a mesma compra é reconhecida pelo lugar, pelo valor e pela ordem:
  /// a liquidação vem depois, com o mesmo valor, no mesmo estabelecimento.
  /// Cada liquidação responde por uma autorização só — duas passagens iguais
  /// de ônibus na mesma semana não podem sumir juntas.
  ///
  /// [concluidas] são autorizações que já liquidaram: não voltam para a tela,
  /// só emprestam à liquidação a hora em que a compra foi feita.
  void _applyPendingCard(
    List<LedgerEntry> recebidas, {
    List<LedgerEntry> concluidas = const [],
  }) {
    final liquidadas = _entries
        .where((e) => e.kind == LedgerKind.cardPurchase)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final usadas = <String>{};

    LedgerEntry? liquidacaoDe(LedgerEntry autorizacao) {
      final chave = _merchantKey(autorizacao);
      final valor = autorizacao.change.abs();
      final inicio = autorizacao.time.subtract(const Duration(hours: 1));
      final fim = autorizacao.time.add(_prazoDeLiquidacao);
      for (final e in liquidadas) {
        if (usadas.contains(e.id)) continue;
        if (e.time.isBefore(inicio) || e.time.isAfter(fim)) continue;
        if (_merchantKey(e) != chave) continue;
        if ((e.change.abs() - valor).abs() >= 0.005) continue;
        usadas.add(e.id);
        return e;
      }
      return null;
    }

    final chegaram = {for (final e in recebidas) e.id};
    final candidatas = {
      for (final e in _pendingAguardando) e.id: e,
      for (final e in _pendingCard) e.id: e,
      // Concluídas antes das pendentes recebidas: se a mesma autorização
      // aparecer nas duas, vale o que a Bybit disse por último sobre ela.
      for (final e in concluidas) e.id: e,
      for (final e in recebidas) e.id: e,
    }.values.toList()
      // A mais antiga primeiro: é a que liquida antes.
      ..sort((a, b) => a.time.compareTo(b.time));

    final visiveis = <LedgerEntry>[];
    final aguardando = <LedgerEntry>[];
    final agora = DateTime.now();
    var moveuAjuste = false;
    var lembrouData = false;

    for (final autorizacao in candidatas) {
      final liquidacao = liquidacaoDe(autorizacao);
      if (liquidacao != null) {
        // Já liquidou: daqui em diante quem conta é a liquidação — mas no dia
        // em que o cartão passou.
        moveuAjuste = _moverAjustes(autorizacao.id, liquidacao.id) || moveuAjuste;
        lembrouData = _lembrarDataDaCompra(autorizacao, liquidacao) || lembrouData;
        continue;
      }
      if (chegaram.contains(autorizacao.id)) {
        visiveis.add(autorizacao);
      } else if (_temAjusteProprio(autorizacao.id) &&
          agora.difference(autorizacao.time) < _prazoDeLiquidacao) {
        aguardando.add(autorizacao);
      }
      // Saiu das pendentes sem ajuste e sem liquidação: foi cancelada, ou a
      // liquidação ainda vai chegar e aparece sozinha quando chegar.
    }

    _pendingCard = visiveis;
    _pendingAguardando = aguardando;

    if (lembrouData) {
      _aplicarDatasDaCompra();
      unawaited(_preferences.savePurchaseDates(_datasDaCompra));
      _syncPreference(_kSyncDatasDaCompra, _datasDaCompra);
    }

    unawaited(_preferences.savePendingCard(visiveis, aguardando));
    if (moveuAjuste) {
      unawaited(_preferences.saveEntryNameOverrides(_entryNameOverrides));
      unawaited(_preferences.saveHiddenEntries(_hiddenIds));
      _syncPreference(_kSyncNomesPorCompra, _entryNameOverrides);
      _syncPreference(_kSyncOcultos, _hiddenIds.toList());
    }
  }

  /// Guarda a hora da autorização como a hora da compra liquidada.
  bool _lembrarDataDaCompra(LedgerEntry autorizacao, LedgerEntry liquidacao) {
    // A autorização vem antes da confirmação. Se viesse depois, o par estaria
    // errado, e a hora da liquidação é a mais segura.
    if (autorizacao.time.isAfter(liquidacao.time) &&
        !_datasDaCompra.containsKey(liquidacao.id)) {
      return false;
    }
    final ms = autorizacao.time.millisecondsSinceEpoch;
    if (_datasDaCompra[liquidacao.id] == ms) return false;
    _datasDaCompra = {..._datasDaCompra, liquidacao.id: ms};
    return true;
  }

  /// Põe cada liquidação conhecida no horário em que a compra foi feita.
  void _aplicarDatasDaCompra() {
    if (_datasDaCompra.isEmpty) return;
    for (var i = 0; i < _entries.length; i++) {
      final ms = _datasDaCompra[_entries[i].id];
      if (ms == null || _entries[i].time.millisecondsSinceEpoch == ms) continue;
      _entries[i] =
          _entries[i].comHorario(DateTime.fromMillisecondsSinceEpoch(ms));
    }
  }

  bool _temAjusteProprio(String id) =>
      _entryNameOverrides.containsKey(id) || _hiddenIds.contains(id);

  /// Passa o nome próprio e a marcação de oculta de um lançamento a outro.
  bool _moverAjustes(String de, String para) {
    var moveu = false;

    final nome = _entryNameOverrides[de];
    if (nome != null) {
      final novo = Map<String, String>.from(_entryNameOverrides)..remove(de);
      // Um nome dado depois de liquidar vence o que veio da pendente.
      novo.putIfAbsent(para, () => nome);
      _entryNameOverrides = novo;
      moveu = true;
    }

    if (_hiddenIds.contains(de)) {
      _hiddenIds = {..._hiddenIds}
        ..remove(de)
        ..add(para);
      moveu = true;
    }

    return moveu;
  }

  /// Aplica pendentes direto, sem passar pela rede, para os testes.
  @visibleForTesting
  void seedPending(
    List<LedgerEntry> recebidas, {
    List<LedgerEntry> concluidas = const [],
  }) =>
      _applyPendingCard(recebidas, concluidas: concluidas);

  /// Quanto foi gasto no cartão no mês corrente, na moeda original das compras.
  double get cardSpentThisMonth {
    final now = DateTime.now();
    return cardSpentInMonth(DateTime(now.year, now.month));
  }

  /// Moeda predominante das compras do cartão, para rotular os totais.
  String get cardCurrency =>
      cardEntries.isEmpty ? 'BRL' : cardEntries.first.coin;

  /// Gasto por categoria no mês corrente, da maior para a menor.
  List<MapEntry<String, double>> get cardCategoriesThisMonth {
    final now = DateTime.now();
    return categoryBreakdown(DateTime(now.year, now.month))
        .map((c) => MapEntry(c.label, c.total))
        .toList();
  }

  /// Todas as moedas com saldo, das duas carteiras, da maior para a menor.
  /// A mesma moeda aparece uma vez por carteira, para ficar claro onde está.
  List<CoinBalance> get allCoins {
    final list = [...snapshot.activeCoins, ...fundingCoins]
      ..sort((a, b) => b.usdValue.compareTo(a.usdValue));
    return list;
  }

  /// Saldo somado por moeda, juntando as carteiras. É o que faz sentido num
  /// gráfico de alocação: BRL é BRL, esteja onde estiver.
  List<MapEntry<String, double>> get allocationByCoin {
    final totals = <String, double>{};
    for (final c in allCoins) {
      if (c.usdValue <= 0) continue;
      totals[c.coin] = (totals[c.coin] ?? 0) + c.usdValue;
    }
    final list = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// Carrega credenciais salvas e, se existirem, já busca os dados.
  Future<void> boot() async {
    // Sem projeto configurado isto é um no-op e o app segue só local.
    //
    // Com prazo: a sincronização é um extra, e o app não pode ficar preso na
    // tela de carregamento se o servidor demorar a responder.
    try {
      await _cloud.init().timeout(const Duration(seconds: 8));
      _watchAuth();
    } catch (_) {
      // Falha ou demora ao ligar a nuvem não impede o app de abrir.
    }

    skippedLogin = await _preferences.loadSkippedLogin();

    // Os ajustes antigos foram gravados por grafia; passam a valer por marca.
    _categoryOverrides = _migrateKeys(await _preferences.loadCategoryOverrides());
    _nameOverrides = _migrateKeys(await _preferences.loadNameOverrides());
    _entryNameOverrides = await _preferences.loadEntryNameOverrides();
    _fixedOverrides = _migrateKeys(await _preferences.loadFixedOverrides());
    _dueDayOverrides = _migrateKeys(await _preferences.loadDueDays());
    _hiddenIds = await _preferences.loadHiddenEntries();
    useOnlineLogos = await _preferences.loadOnlineLogos();
    _showInBrl = await _preferences.loadShowInBrl();
    cardGoalUsd = await _preferences.loadCardGoal() ?? defaultCardGoalUsd;
    budgetNodes = await _preferences.loadBudgetTree() ?? defaultBudgetTree();
    _planejamentoPendente = await _preferences.loadBudgetPending();
    manualSubscriptions = await _preferences.loadManualSubscriptions();
    _cancelledSubscriptions = await _preferences.loadCancelledSubscriptions();

    // O histórico guardado entra antes da rede: o app já abre com os meses
    // que a Bybit não devolve mais.
    _entries.addAll(await _preferences.loadCachedEntries());
    _datasDaCompra = await _preferences.loadPurchaseDates();
    _aplicarDatasDaCompra();

    // As pendentes da última abertura voltam também: a próxima atualização
    // corrige o que tiver mudado, e o nome dado a uma delas não se perde.
    final pendentes = await _preferences.loadPendingCard();
    _pendingCard = pendentes.visiveis;
    _pendingAguardando = pendentes.aguardando;

    final saved = await _store.load();
    if (saved == null || !saved.isValid) {
      phase = LoadPhase.needsSetup;
      notifyListeners();
      return;
    }
    _credentials = saved;
    _client = BybitClient(
      apiKey: saved.apiKey,
      apiSecret: saved.apiSecret,
      testnet: saved.testnet,
    );
    await refresh();
  }

  /// Valida as credenciais na Bybit antes de gravá-las.
  /// O que a Bybit disse sobre a chave em uso, na última consulta.
  ApiKeyInfo? apiKeyInfo;

  /// Aviso sobre a chave aceita na última conexão: algo que não impede de
  /// usar o app, mas deixa uma parte dele vazia.
  String? connectWarning;

  /// Dias até a chave vencer. Nulo quando ela não vence ou ainda não se sabe.
  int? get keyDaysLeft => apiKeyInfo?.daysLeft(DateTime.now());

  /// Com quantos dias de antecedência o app começa a avisar do vencimento.
  static const keyWarningDays = 14;

  /// A chave vence logo. Avisar antes é o que evita descobrir pelo app parado.
  bool get keyExpiresSoon {
    final dias = keyDaysLeft;
    return dias != null && dias <= keyWarningDays;
  }

  /// Por que uma chave não pode ser usada, ou nulo quando pode.
  ///
  /// O app promete que só lê. Uma chave que negocia ou saca desmente a
  /// promessa — e, se vazar, abre caminho até o dinheiro. Melhor recusar na
  /// porta do que guardar.
  static String? keyProblem(ApiKeyInfo info) {
    if (info.canWithdraw) {
      return 'Essa chave tem permissão de saque. Por segurança, crie uma '
          'chave "Read-Only" (somente leitura) e cole aqui.';
    }
    if (!info.readOnly) {
      return 'Essa chave pode negociar e movimentar a conta. O app só precisa '
          'ler: crie uma chave "Read-Only" (somente leitura) e cole aqui.';
    }
    return null;
  }

  Future<String?> connect(Credentials c) async {
    final client = BybitClient(
      apiKey: c.apiKey.trim(),
      apiSecret: c.apiSecret.trim(),
      testnet: c.testnet,
    );
    try {
      await client.ping();
    } on BybitException catch (e) {
      if (e.isAuth) {
        return 'A Bybit não aceitou essa chave. Confira se copiou a API Key e '
            'a API Secret inteiras, e se a chave não foi apagada ou venceu.';
      }
      if (e.isClockSkew) {
        return 'O relógio deste dispositivo está fora de hora. Ative o ajuste '
            'automático de data e hora no sistema e tente de novo.';
      }
      return 'A Bybit respondeu: ${e.message}';
    } catch (e) {
      return 'Não foi possível falar com a Bybit. Verifique sua conexão. ($e)';
    }

    // Com a chave aceita, confere o que ela libera. Se a própria consulta
    // falhar, segue em frente: melhor conectar sem a conferência do que
    // barrar a entrada por causa dela.
    ApiKeyInfo? info;
    try {
      info = await client.apiKeyInfo();
    } catch (_) {
      // Sem a informação, a chave vale como veio.
    }

    if (info != null) {
      final problema = keyProblem(info);
      if (problema != null) return problema;
    }

    connectWarning = info != null && !info.canReadCard
        ? 'A chave não tem a permissão do cartão: saldos e extrato aparecem, '
            'mas as compras do Bybit Card não. Crie outra marcando a '
            'permissão do cartão.'
        : null;
    apiKeyInfo = info;

    // Guardar a chave pode falhar: o cofre do navegador exige contexto
    // seguro, e um endereço servido por HTTP puro não é. A conexão continua
    // valendo na sessão, mas o usuário precisa saber que não ficou salva.
    credentialsPersisted = true;
    try {
      await _store.save(c);
    } catch (_) {
      credentialsPersisted = false;
    }

    _credentials = c;
    _client = client;
    _entries.clear();
    _cursor = null;
    await refresh();
    return null;
  }

  Future<void> disconnect() async {
    await _store.clear();
    _client = null;
    _credentials = null;
    _entries.clear();
    // A chave e as compras pendentes eram da conta que saiu.
    _pendingCard = const [];
    _pendingAguardando = const [];
    unawaited(_preferences.savePendingCard(const [], const []));
    apiKeyInfo = null;
    connectWarning = null;
    _cursor = null;
    snapshot = WalletSnapshot.empty();
    lastSync = null;
    phase = LoadPhase.needsSetup;
    notifyListeners();
  }

  /// Recarrega saldo, extrato e cotações.
  Future<void> refresh() async {
    final client = _client;
    if (client == null) {
      phase = LoadPhase.needsSetup;
      notifyListeners();
      return;
    }

    if (phase != LoadPhase.ready) {
      phase = LoadPhase.loading;
      errorMessage = null;
      notifyListeners();
    }

    try {
      final wallet = await client.walletBalance();

      // Cotações primeiro: o valor em dólar da carteira de fundos depende delas.
      final priceMap = await _optional(client.spotPrices(), const <String, double>{});
      final rate = await _fx.usdToBrl();
      prices = priceMap;
      if (rate != null) usdBrl = rate;

      final funding = await _optional(client.fundingBalance(), const <CoinBalance>[]);

      // O extrato da conta unificada é a fonte principal; o resto complementa
      // e não pode derrubar a sincronização se falhar.
      final page = await _optional(
        client.transactionLog(limit: 50),
        LedgerPage(entries: const []),
      );
      final transfers = await _optional(
        client.internalTransfers(limit: 50),
        LedgerPage(entries: const []),
      );
      final deposits = await _optional(client.deposits(limit: 50), const <LedgerEntry>[]);
      final internalDeposits =
          await _optional(client.internalDeposits(limit: 50), const <LedgerEntry>[]);
      final withdrawals = await _optional(client.withdrawals(limit: 50), const <LedgerEntry>[]);

      // Bybit Card: compras e programa de pontos. O histórico inteiro é
      // carregado de uma vez, para os meses anteriores já virem prontos.
      final card = await _optional(
        _fetchAllCardPages(client),
        CardPage(entries: const [], page: 1, pageSize: _cardPageSize, totalCount: 0),
      );
      cardRewards = await _optional(client.cardRewards(), CardRewards.empty);
      // A situação da chave muda com o tempo: o vencimento se aproxima.
      apiKeyInfo = await _optional<ApiKeyInfo?>(client.apiKeyInfo(), apiKeyInfo);

      snapshot = wallet;
      fundingCoins = funding
          .map((c) => c.withUsdValue(usdValueOf(c.coin, c.walletBalance)))
          .toList()
        ..sort((a, b) => b.usdValue.compareTo(a.usdValue));

      // O que já foi visto continua valendo: a API só acrescenta. Sem isso,
      // cada sincronização apagaria os meses que saíram da janela da Bybit.
      _mergeUnique(page.entries);
      _mergeUnique(transfers.entries);
      _mergeUnique(deposits);
      _mergeUnique(internalDeposits);
      _mergeUnique(withdrawals);
      _mergeUnique(card.entries);

      // Compras que o cartão já passou e o estabelecimento ainda não
      // confirmou. Vêm depois das liquidadas, porque é contra elas que a mesma
      // compra é reconhecida quando liquida.
      try {
        final autorizacoes = await client.cardAuthorizations();
        _applyPendingCard(
          autorizacoes.pendentes,
          concluidas: autorizacoes.concluidas,
        );
      } catch (_) {
        // O limite de consultas deste endpoint é apertado. Falhou, fica a
        // lista anterior: sai da tela quem deixou de estar pendente, não quem
        // só não respondeu a tempo.
      }

      _cursor = page.nextCursor;
      _logHasMore = page.hasMore;
      _cardPage = card.page;
      _cardHasMore = card.hasMore;
      cardTotalCount = card.totalCount;
      // Só as liquidadas: é com o total do histórico que este número se compara.
      cardLoadedCount = _entries.where((e) => e.isCard).length;
      lastSync = DateTime.now();

      // Guarda o acumulado para a próxima abertura e leva para os outros
      // aparelhos, se a sincronização estiver ligada.
      await _preferences.saveCachedEntries(_entries);
      unawaited(syncWithCloud(pushOnly: true));
      errorMessage = null;
      phase = LoadPhase.ready;
    } on BybitException catch (e) {
      if (e.isAuth) {
        errorMessage =
            (keyDaysLeft ?? 0) < 0
                ? 'Sua chave da Bybit venceu. Ela vence em 90 dias quando não '
                    'está presa a um IP: crie outra e troque em Ajustes.'
                : 'A Bybit recusou a chave de API. Vá em Ajustes e confira as '
                    'credenciais.';
      } else if (e.isClockSkew) {
        errorMessage = 'O relógio deste dispositivo está fora de hora e a Bybit '
            'recusou as requisições. Ajuste a data e a hora automaticamente nas '
            'configurações do sistema e tente de novo.';
      } else {
        errorMessage = 'Bybit: ${e.message}';
      }
      phase = LoadPhase.failed;
    } catch (e) {
      errorMessage = 'Falha ao carregar os dados: $e';
      phase = LoadPhase.failed;
    }
    notifyListeners();
  }

  /// A API do cartão aceita até 500 registros por página.
  static const _cardPageSize = 500;

  /// Teto de páginas, para uma resposta estranha da API não virar um laço
  /// infinito de requisições.
  static const _cardPageLimit = 6;

  /// Traz todo o histórico do cartão, juntando as páginas necessárias.
  Future<CardPage> _fetchAllCardPages(BybitClient client) async {
    final primeira = await client.cardTransactions(page: 1, pageSize: _cardPageSize);
    final todas = <LedgerEntry>[...primeira.entries];

    var pagina = 1;
    var restam = primeira.totalCount - _cardPageSize;
    while (restam > 0 && pagina < _cardPageLimit) {
      // O endpoint do cartão limita a frequência de chamadas.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      pagina++;
      final proxima =
          await client.cardTransactions(page: pagina, pageSize: _cardPageSize);
      if (proxima.entries.isEmpty && proxima.totalCount == 0) break;
      todas.addAll(proxima.entries);
      restam -= _cardPageSize;
    }

    return CardPage(
      entries: todas,
      page: pagina,
      pageSize: _cardPageSize,
      totalCount: primeira.totalCount,
    );
  }

  // ---------------------------------------------------------------------
  // Sincronização entre aparelhos
  // ---------------------------------------------------------------------

  /// Chaves usadas tanto no armazenamento local quanto na nuvem.
  static const _kSyncCategorias = 'category_overrides';
  static const _kSyncNomes = 'name_overrides';
  static const _kSyncOcultos = 'hidden_entries';
  static const _kSyncPlanejamento = 'budget_tree';
  static const _kSyncDatasDaCompra = 'purchase_dates';
  static const _kSyncMetaCartao = 'card_goal_usd';
  static const _kSyncFixos = 'fixed_overrides';
  static const _kSyncMoeda = 'show_in_brl';
  static const _kSyncVencimentos = 'due_days';
  static const _kSyncNomesPorCompra = 'entry_name_overrides';
  static const _kSyncAssinaturas = 'manual_subscriptions';
  static const _kSyncAssinaturasCanceladas = 'cancelled_subscriptions';

  /// Junta o que está na nuvem com o que está neste aparelho.
  ///
  /// Transações são fatos: a união dos dois lados é sempre o conjunto certo,
  /// e é o que preserva os meses que a Bybit apagou. Já os ajustes seguem o
  /// que veio da nuvem, para um aparelho novo adotar a configuração dos
  /// outros em vez de sobrescrevê-la com o padrão.
  Future<void> syncWithCloud({bool pushOnly = false}) async {
    if (!_cloud.available || !_cloud.signedIn || cloudSyncing) return;

    cloudSyncing = true;
    cloudError = null;
    notifyListeners();

    try {
      if (!pushOnly) {
        final remotos = await _cloud.pullEntries();
        if (remotos.isNotEmpty) {
          _mergeUnique(remotos);
          await _preferences.saveCachedEntries(_entries);
        }

        final ajustes = await _cloud.pullPreferences();
        _applyRemotePreferences(ajustes);
      }

      await _cloud.pushEntries(_entries);
      await _pushAllPreferences();

      cloudLastSync = DateTime.now();
    } catch (e) {
      cloudError = 'Não foi possível sincronizar: $e';
    }

    cloudSyncing = false;
    notifyListeners();
  }

  void _applyRemotePreferences(Map<String, dynamic> ajustes) {
    Map<String, String> comoMapa(dynamic v) => v is Map
        ? v.map((k, valor) => MapEntry(k.toString(), valor.toString()))
        : {};

    if (ajustes.containsKey(_kSyncCategorias)) {
      _categoryOverrides = _migrateKeys(comoMapa(ajustes[_kSyncCategorias]));
    }
    if (ajustes.containsKey(_kSyncNomes)) {
      _nameOverrides = _migrateKeys(comoMapa(ajustes[_kSyncNomes]));
    }
    // Estes são por transação: a chave é o identificador do lançamento, que
    // não muda de aparelho para aparelho.
    if (ajustes.containsKey(_kSyncNomesPorCompra)) {
      _entryNameOverrides = comoMapa(ajustes[_kSyncNomesPorCompra]);
    }
    if (ajustes[_kSyncFixos] is Map) {
      _fixedOverrides = _migrateKeys((ajustes[_kSyncFixos] as Map)
          .map((k, v) => MapEntry(k.toString(), v == true)));
    }
    if (ajustes[_kSyncVencimentos] is Map) {
      _dueDayOverrides = _migrateKeys(
        (ajustes[_kSyncVencimentos] as Map).map(
          (k, v) => MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0),
        )..removeWhere((_, dia) => dia < 1 || dia > 31),
      );
    }
    if (ajustes[_kSyncOcultos] is List) {
      _hiddenIds =
          (ajustes[_kSyncOcultos] as List).map((e) => e.toString()).toSet();
    }
    // Com mudança daqui ainda não enviada, a árvore da nuvem é a mais velha:
    // fica a deste aparelho, que o envio logo em seguida leva para a nuvem.
    if (ajustes[_kSyncPlanejamento] is List && !_planejamentoPendente) {
      final nos = (ajustes[_kSyncPlanejamento] as List)
          .map((e) => BudgetNode.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (nos.isNotEmpty) budgetNodes = nos;
    }
    if (ajustes[_kSyncAssinaturas] is List) {
      manualSubscriptions = (ajustes[_kSyncAssinaturas] as List)
          .whereType<Map>()
          .map((e) => ManualSubscription.fromJson(Map<String, dynamic>.from(e)))
          .whereType<ManualSubscription>()
          .toList();
    }
    if (ajustes[_kSyncAssinaturasCanceladas] is List) {
      _cancelledSubscriptions = (ajustes[_kSyncAssinaturasCanceladas] as List)
          .map((e) => e.toString())
          .toSet();
    }
    if (ajustes[_kSyncDatasDaCompra] is Map) {
      // Datas são fatos: junta os dois lados, e o que foi visto aqui fica.
      final remotas = {
        for (final e in (ajustes[_kSyncDatasDaCompra] as Map).entries)
          if (int.tryParse(e.value.toString()) case final ms?)
            e.key.toString(): ms,
      };
      _datasDaCompra = {...remotas, ..._datasDaCompra};
      _aplicarDatasDaCompra();
      _preferences.savePurchaseDates(_datasDaCompra);
    }
    if (ajustes[_kSyncMetaCartao] is num) {
      cardGoalUsd = (ajustes[_kSyncMetaCartao] as num).toDouble();
    }
    if (ajustes[_kSyncMoeda] is bool) {
      _showInBrl = ajustes[_kSyncMoeda] as bool;
      _preferences.saveShowInBrl(_showInBrl);
    }

    // O que veio da nuvem passa a valer também neste aparelho.
    _preferences.saveCategoryOverrides(_categoryOverrides);
    _preferences.saveNameOverrides(_nameOverrides);
    _preferences.saveEntryNameOverrides(_entryNameOverrides);
    _preferences.saveFixedOverrides(_fixedOverrides);
    _preferences.saveDueDays(_dueDayOverrides);
    _preferences.saveHiddenEntries(_hiddenIds);
    _preferences.saveBudgetTree(budgetNodes);
    _preferences.saveCardGoal(cardGoalUsd);
    _preferences.saveManualSubscriptions(manualSubscriptions);
    _preferences.saveCancelledSubscriptions(_cancelledSubscriptions);
  }

  Future<void> _pushAllPreferences() async {
    await _cloud.pushPreference(_kSyncCategorias, _categoryOverrides);
    await _cloud.pushPreference(_kSyncNomes, _nameOverrides);
    await _cloud.pushPreference(_kSyncNomesPorCompra, _entryNameOverrides);
    await _cloud.pushPreference(_kSyncFixos, _fixedOverrides);
    await _cloud.pushPreference(_kSyncVencimentos, _dueDayOverrides);
    await _cloud.pushPreference(_kSyncOcultos, _hiddenIds.toList());
    final versao = _versaoDoPlanejamento;
    await _cloud.pushPreference(
      _kSyncPlanejamento,
      budgetNodes.map((n) => n.toJson()).toList(),
    );
    if (versao == _versaoDoPlanejamento) _marcarPlanejamentoPendente(false);
    await _cloud.pushPreference(_kSyncDatasDaCompra, _datasDaCompra);
    await _cloud.pushPreference(_kSyncMetaCartao, cardGoalUsd);
    await _cloud.pushPreference(_kSyncMoeda, _showInBrl);
    await _cloud.pushPreference(
      _kSyncAssinaturas,
      manualSubscriptions.map((m) => m.toJson()).toList(),
    );
    await _cloud.pushPreference(
      _kSyncAssinaturasCanceladas,
      _cancelledSubscriptions.toList(),
    );
  }

  /// Manda um ajuste para a nuvem sem travar quem chamou.
  void _syncPreference(String chave, dynamic valor) {
    if (!_cloud.available || !_cloud.signedIn) return;
    _cloud.pushPreference(chave, valor).catchError((_) {
      // Falha de rede não pode atrapalhar o uso: a próxima sincronização
      // completa reenvia tudo.
    });
  }

  /// Intervalo abaixo do qual não vale a pena buscar de novo.
  static const _staleAfter = Duration(minutes: 2);

  /// Busca dados novos se os atuais já estiverem velhos. Usado quando o app
  /// volta ao primeiro plano.
  Future<void> refreshIfStale() async {
    if (!isConfigured || phase == LoadPhase.loading) return;
    final ultima = lastSync;
    if (ultima != null && DateTime.now().difference(ultima) < _staleAfter) return;
    await refresh();
  }

  /// Próxima página do extrato: primeiro esgota a conta unificada, depois
  /// segue paginando as compras do cartão.
  Future<void> loadMore() async {
    final client = _client;
    if (client == null || loadingMore || !hasMore) return;
    loadingMore = true;
    notifyListeners();

    try {
      if (_logHasMore) {
        final page = await client.transactionLog(cursor: _cursor, limit: 50);
        _mergeUnique(page.entries);
        _cursor = page.nextCursor;
        _logHasMore = page.hasMore;
      } else if (_cardHasMore) {
        final card = await client.cardTransactions(
            page: _cardPage + 1, pageSize: _cardPageSize);
        _mergeUnique(card.entries);
        _cardPage = card.page;
        _cardHasMore = card.hasMore;
      }
    } catch (_) {
      _logHasMore = false;
      _cardHasMore = false;
    }

    loadingMore = false;
    notifyListeners();
  }

  bool loadingCardHistory = false;
  int cardLoadedCount = 0;
  int cardTotalCount = 0;

  bool get canLoadMoreCard => _cardHasMore;

  /// Puxa todas as páginas restantes de compras do cartão. O endpoint tem
  /// limite de chamadas apertado, por isso as páginas vêm espaçadas.
  Future<void> loadFullCardHistory() async {
    final client = _client;
    if (client == null || loadingCardHistory || !_cardHasMore) return;

    loadingCardHistory = true;
    notifyListeners();

    try {
      while (_cardHasMore) {
        final card = await client.cardTransactions(
            page: _cardPage + 1, pageSize: _cardPageSize);
        _mergeUnique(card.entries);
        _cardPage = card.page;
        _cardHasMore = card.hasMore;
        cardTotalCount = card.totalCount;
        cardLoadedCount = cardEntries.length;
        notifyListeners();
        if (_cardHasMore) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }
    } catch (_) {
      // Mantém o que já veio; o botão continua disponível para tentar de novo.
    }

    loadingCardHistory = false;
    notifyListeners();
  }

  /// Chamadas acessórias não devem derrubar a sincronização inteira.
  Future<T> _optional<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } catch (_) {
      return fallback;
    }
  }

  /// Popula o extrato direto, sem passar pela rede, para os testes.
  @visibleForTesting
  void seedEntries(List<LedgerEntry> entries) {
    _entries
      ..clear()
      ..addAll(entries);
  }

  void _mergeUnique(List<LedgerEntry> incoming) {
    final seen = _entries.map((e) => e.id).toSet();
    for (final e in incoming) {
      if (seen.add(e.id)) _entries.add(e);
    }
    // O que chega da Bybit vem com a hora da liquidação; a da compra já
    // conhecida volta a valer.
    _aplicarDatasDaCompra();
  }

  void setFilter(LedgerFilter f) {
    filter = f;
    notifyListeners();
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  /// Alterna entre real e dólar. A escolha fica guardada e vale nos outros
  /// aparelhos.
  Future<void> toggleCurrency() async {
    if (usdBrl == null) return;
    _showInBrl = !_showInBrl;
    notifyListeners();
    await _preferences.saveShowInBrl(_showInBrl);
    _syncPreference(_kSyncMoeda, _showInBrl);
  }

  void toggleHideBalances() {
    hideBalances = !hideBalances;
    notifyListeners();
  }
}
