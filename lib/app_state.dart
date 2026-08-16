import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;

import 'budget.dart';
import 'models.dart';
import 'services/bybit_client.dart';
import 'services/cloud_sync.dart';
import 'services/credentials.dart';
import 'services/fx.dart';
import 'services/preferences.dart';
import 'util/categorizer.dart';
import 'util/format.dart';

enum LoadPhase { booting, needsSetup, loading, ready, failed }

/// Quanto uma categoria representou nos gastos de um período.
class CategoryTotal {
  const CategoryTotal({
    required this.label,
    required this.total,
    required this.count,
    required this.share,
  });

  final String label;
  final double total;
  final int count;

  /// Fatia do gasto do período, de 0 a 1.
  final double share;
}

/// Filtros disponíveis no extrato.
enum LedgerFilter { all, card, incoming, outgoing, transfers, deposits, withdrawals, trades }

String ledgerFilterLabel(LedgerFilter f) {
  switch (f) {
    case LedgerFilter.all:
      return 'Tudo';
    case LedgerFilter.card:
      return 'Cartão';
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
  bool showInBrl = false;
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
    final list = _entries.where((e) {
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

  /// Chave usada para guardar a correção de um estabelecimento.
  String _merchantKey(LedgerEntry e) => (e.note ?? '').trim().toLowerCase();

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

  /// Nome a exibir: o apelido dado pelo usuário vence o que a Bybit mandou.
  String displayNameOf(LedgerEntry e) {
    final key = _merchantKey(e);
    if (key.isNotEmpty) {
      final override = _nameOverrides[key];
      if (override != null && override.isNotEmpty) return override;
    }
    return e.note ?? kindLabel(e.kind, e.rawType);
  }

  /// Nome original, como veio da Bybit.
  String? originalNameOf(LedgerEntry e) => e.note;

  bool hasCustomCategory(LedgerEntry e) =>
      _categoryOverrides.containsKey(_merchantKey(e));

  bool hasCustomName(LedgerEntry e) =>
      _nameOverrides.containsKey(_merchantKey(e));

  bool hasCustomizations(LedgerEntry e) =>
      hasCustomCategory(e) || hasCustomName(e);

  /// Grava nome e categoria de um estabelecimento de uma vez. Ambos valem
  /// para todas as compras do mesmo lugar, inclusive as futuras.
  ///
  /// Passar `null` mantém o valor atual; passar vazio no nome remove o apelido.
  Future<void> setEntryOverrides(
    LedgerEntry e, {
    String? name,
    String? category,
  }) async {
    final key = _merchantKey(e);
    if (key.isEmpty) return;

    if (category != null) {
      _categoryOverrides = {..._categoryOverrides, key: category};
    }

    if (name != null) {
      final limpo = name.trim();
      final novo = Map<String, String>.from(_nameOverrides);
      // Apelido igual ao original não é personalização.
      if (limpo.isEmpty || limpo == (e.note ?? '').trim()) {
        novo.remove(key);
      } else {
        novo[key] = limpo;
      }
      _nameOverrides = novo;
    }

    notifyListeners();
    await _preferences.saveCategoryOverrides(_categoryOverrides);
    await _preferences.saveNameOverrides(_nameOverrides);
    _syncPreference(_kSyncCategorias, _categoryOverrides);
    _syncPreference(_kSyncNomes, _nameOverrides);
  }

  /// Devolve o estabelecimento ao nome e à categoria automáticos.
  Future<void> clearOverridesFor(LedgerEntry e) async {
    final key = _merchantKey(e);
    if (!_categoryOverrides.containsKey(key) && !_nameOverrides.containsKey(key)) {
      return;
    }
    _categoryOverrides = Map<String, String>.from(_categoryOverrides)..remove(key);
    _nameOverrides = Map<String, String>.from(_nameOverrides)..remove(key);
    notifyListeners();
    await _preferences.saveCategoryOverrides(_categoryOverrides);
    await _preferences.saveNameOverrides(_nameOverrides);
    _syncPreference(_kSyncCategorias, _categoryOverrides);
    _syncPreference(_kSyncNomes, _nameOverrides);
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

  /// Estabelecimentos fixos do mês, do maior para o menor — é a lista de
  /// compromissos que se repetem.
  List<MapEntry<String, double>> fixedMerchants(DateTime month) {
    final totais = <String, double>{};
    for (final e in cardEntries) {
      if (e.kind != LedgerKind.cardPurchase || isHidden(e)) continue;
      if (e.time.year != month.year || e.time.month != month.month) continue;
      if (!isFixed(e)) continue;
      final nome = displayNameOf(e);
      totais[nome] = (totais[nome] ?? 0) + e.change.abs();
    }
    final lista = totais.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return lista;
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
    _syncPreference(
      _kSyncPlanejamento,
      budgetNodes.map((n) => n.toJson()).toList(),
    );
  }

  /// Define a meta mensal de uma categoria ou subcategoria, em reais.
  Future<void> setBudget(String nodeId, double value) async {
    budgetNodes = budgetNodes
        .map((n) => n.id == nodeId ? n.copyWith(budget: value < 0 ? 0 : value) : n)
        .toList();
    await _persistBudget();
  }

  Future<void> renameBudgetNode(String nodeId, String name) async {
    final limpo = name.trim();
    if (limpo.isEmpty) return;
    budgetNodes =
        budgetNodes.map((n) => n.id == nodeId ? n.copyWith(name: limpo) : n).toList();
    await _persistBudget();
  }

  /// Cria uma categoria principal ou uma subcategoria de [parentId].
  Future<void> addBudgetNode({
    required String name,
    String? parentId,
    double budget = 0,
    List<String> sources = const [],
  }) async {
    final limpo = name.trim();
    if (limpo.isEmpty) return;

    final id = 'user_${DateTime.now().microsecondsSinceEpoch}';
    budgetNodes = [
      // Uma categoria de gasto pertence a um nó só, senão o mesmo dinheiro
      // seria contado duas vezes no planejamento.
      ..._withoutSources(budgetNodes, sources),
      BudgetNode(
        id: id,
        name: limpo,
        parentId: parentId,
        budget: budget,
        sources: sources,
      ),
    ];
    await _persistBudget();
  }

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

  /// Remove uma categoria criada pelo usuário, junto das subcategorias dela.
  Future<void> removeBudgetNode(String nodeId) async {
    final node = budgetNodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null || node.builtIn) return;
    budgetNodes = budgetNodes
        .where((n) => n.id != nodeId && n.parentId != nodeId)
        .toList();
    await _persistBudget();
  }

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
    final list = _entries.where((e) => e.isCard).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

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
    } catch (_) {
      // Falha ou demora ao ligar a nuvem não impede o app de abrir.
    }

    _categoryOverrides = await _preferences.loadCategoryOverrides();
    _nameOverrides = await _preferences.loadNameOverrides();
    _fixedOverrides = await _preferences.loadFixedOverrides();
    _hiddenIds = await _preferences.loadHiddenEntries();
    useOnlineLogos = await _preferences.loadOnlineLogos();
    cardGoalUsd = await _preferences.loadCardGoal() ?? defaultCardGoalUsd;
    budgetNodes = await _preferences.loadBudgetTree() ?? defaultBudgetTree();

    // O histórico guardado entra antes da rede: o app já abre com os meses
    // que a Bybit não devolve mais.
    _entries.addAll(await _preferences.loadCachedEntries());

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
        return 'Chave rejeitada pela Bybit: ${e.message}. Confira a API Key, '
            'o Secret e se o IP está liberado.';
      }
      if (e.isClockSkew) {
        return 'O relógio deste dispositivo está fora de hora. Ative o ajuste '
            'automático de data e hora no sistema e tente de novo.';
      }
      return 'A Bybit respondeu: ${e.message}';
    } catch (e) {
      return 'Não foi possível falar com a Bybit. Verifique sua conexão. ($e)';
    }

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

      _cursor = page.nextCursor;
      _logHasMore = page.hasMore;
      _cardPage = card.page;
      _cardHasMore = card.hasMore;
      cardTotalCount = card.totalCount;
      cardLoadedCount = cardEntries.length;
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
            'A Bybit recusou a chave de API. Vá em Configurações e confira as credenciais.';
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
  static const _kSyncMetaCartao = 'card_goal_usd';
  static const _kSyncFixos = 'fixed_overrides';

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
      _categoryOverrides = comoMapa(ajustes[_kSyncCategorias]);
    }
    if (ajustes.containsKey(_kSyncNomes)) {
      _nameOverrides = comoMapa(ajustes[_kSyncNomes]);
    }
    if (ajustes[_kSyncFixos] is Map) {
      _fixedOverrides = (ajustes[_kSyncFixos] as Map)
          .map((k, v) => MapEntry(k.toString(), v == true));
    }
    if (ajustes[_kSyncOcultos] is List) {
      _hiddenIds =
          (ajustes[_kSyncOcultos] as List).map((e) => e.toString()).toSet();
    }
    if (ajustes[_kSyncPlanejamento] is List) {
      final nos = (ajustes[_kSyncPlanejamento] as List)
          .map((e) => BudgetNode.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (nos.isNotEmpty) budgetNodes = nos;
    }
    if (ajustes[_kSyncMetaCartao] is num) {
      cardGoalUsd = (ajustes[_kSyncMetaCartao] as num).toDouble();
    }

    // O que veio da nuvem passa a valer também neste aparelho.
    _preferences.saveCategoryOverrides(_categoryOverrides);
    _preferences.saveNameOverrides(_nameOverrides);
    _preferences.saveFixedOverrides(_fixedOverrides);
    _preferences.saveHiddenEntries(_hiddenIds);
    _preferences.saveBudgetTree(budgetNodes);
    _preferences.saveCardGoal(cardGoalUsd);
  }

  Future<void> _pushAllPreferences() async {
    await _cloud.pushPreference(_kSyncCategorias, _categoryOverrides);
    await _cloud.pushPreference(_kSyncNomes, _nameOverrides);
    await _cloud.pushPreference(_kSyncFixos, _fixedOverrides);
    await _cloud.pushPreference(_kSyncOcultos, _hiddenIds.toList());
    await _cloud.pushPreference(
      _kSyncPlanejamento,
      budgetNodes.map((n) => n.toJson()).toList(),
    );
    await _cloud.pushPreference(_kSyncMetaCartao, cardGoalUsd);
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
  }

  void setFilter(LedgerFilter f) {
    filter = f;
    notifyListeners();
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  void toggleCurrency() {
    if (usdBrl == null) return;
    showInBrl = !showInBrl;
    notifyListeners();
  }

  void toggleHideBalances() {
    hideBalances = !hideBalances;
    notifyListeners();
  }
}
