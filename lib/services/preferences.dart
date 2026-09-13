import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../budget.dart';
import '../models.dart';
import '../subscriptions.dart';

/// Ajustes do usuário que ficam guardados no dispositivo.
///
/// As correções são indexadas pelo nome original do estabelecimento, para que
/// valham também para as próximas compras no mesmo lugar.
class PreferencesStore {
  static const _storage = FlutterSecureStorage();
  static const _kCategoryOverrides = 'category_overrides';
  static const _kNameOverrides = 'name_overrides';
  static const _kEntryNameOverrides = 'entry_name_overrides';
  static const _kFixedOverrides = 'fixed_overrides';
  static const _kDueDays = 'due_days';
  static const _kHiddenEntries = 'hidden_entries';
  static const _kOnlineLogos = 'online_logos';
  static const _kShowInBrl = 'show_in_brl';
  static const _kSkippedLogin = 'skipped_login';
  static const _kCardGoal = 'card_goal_usd';
  static const _kBudgetTree = 'budget_tree';
  static const _kBudgetPending = 'budget_tree_pending';
  static const _kCachedEntries = 'cached_entries';
  static const _kManualSubscriptions = 'manual_subscriptions';
  static const _kCancelledSubscriptions = 'cancelled_subscriptions';

  Future<Map<String, String>> loadCategoryOverrides() =>
      _loadMap(_kCategoryOverrides);

  Future<void> saveCategoryOverrides(Map<String, String> overrides) =>
      _saveMap(_kCategoryOverrides, overrides);

  Future<Map<String, String>> loadNameOverrides() => _loadMap(_kNameOverrides);

  Future<void> saveNameOverrides(Map<String, String> overrides) =>
      _saveMap(_kNameOverrides, overrides);

  /// Apelidos que valem para uma compra só, pelo identificador dela.
  Future<Map<String, String>> loadEntryNameOverrides() =>
      _loadMap(_kEntryNameOverrides);

  Future<void> saveEntryNameOverrides(Map<String, String> overrides) =>
      _saveMap(_kEntryNameOverrides, overrides);

  /// Estabelecimentos marcados à mão como gasto fixo ou variável.
  Future<Map<String, bool>> loadFixedOverrides() async {
    try {
      final raw = await _storage.read(key: _kFixedOverrides);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v == true));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFixedOverrides(Map<String, bool> overrides) async {
    try {
      if (overrides.isEmpty) {
        await _storage.delete(key: _kFixedOverrides);
        return;
      }
      await _storage.write(key: _kFixedOverrides, value: jsonEncode(overrides));
    } catch (_) {
      // Sem cofre disponível a escolha vale só enquanto o app estiver aberto.
    }
  }

  /// Dias de vencimento definidos à mão, por estabelecimento.
  Future<Map<String, int>> loadDueDays() async {
    try {
      final raw = await _storage.read(key: _kDueDays);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, int.tryParse(v.toString()) ?? 0),
      )..removeWhere((_, dia) => dia < 1 || dia > 31);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveDueDays(Map<String, int> dias) async {
    try {
      if (dias.isEmpty) {
        await _storage.delete(key: _kDueDays);
        return;
      }
      await _storage.write(key: _kDueDays, value: jsonEncode(dias));
    } catch (_) {
      // Sem cofre disponível a escolha vale só enquanto o app estiver aberto.
    }
  }

  /// Se o usuário escolheu usar sem conta, para a tela de entrada não voltar
  /// a cada abertura.
  Future<bool> loadSkippedLogin() async {
    try {
      return (await _storage.read(key: _kSkippedLogin)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> saveSkippedLogin(bool value) async {
    try {
      await _storage.write(key: _kSkippedLogin, value: '$value');
    } catch (_) {
      // Sem cofre a tela reaparece na próxima abertura, o que é aceitável.
    }
  }

  /// Moeda escolhida para exibir os valores. O real é o padrão: é a moeda em
  /// que as compras acontecem.
  Future<bool> loadShowInBrl() async {
    try {
      final raw = await _storage.read(key: _kShowInBrl);
      if (raw == null || raw.isEmpty) return true;
      return raw == 'true';
    } catch (_) {
      return true;
    }
  }

  Future<void> saveShowInBrl(bool value) async {
    try {
      await _storage.write(key: _kShowInBrl, value: '$value');
    } catch (_) {
      // Sem cofre disponível a escolha volta ao padrão na próxima abertura.
    }
  }

  /// Permissão para baixar os logos das marcas. Desligada por padrão: cada
  /// logo é uma requisição a um serviço de terceiros com o nome da marca.
  Future<bool> loadOnlineLogos() async {
    try {
      return (await _storage.read(key: _kOnlineLogos)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> saveOnlineLogos(bool value) async {
    try {
      await _storage.write(key: _kOnlineLogos, value: '$value');
    } catch (_) {
      // Sem cofre disponível a escolha vale só enquanto o app estiver aberto.
    }
  }

  /// Lançamentos já vistos, guardados no dispositivo.
  ///
  /// A Bybit mantém uma janela móvel de mais ou menos seis meses no histórico
  /// de recompensas: o que passa disso some da API. Sem essa cópia local, o
  /// histórico do app encolheria junto.
  Future<List<LedgerEntry>> loadCachedEntries() async {
    try {
      final raw = await _storage.read(key: _kCachedEntries);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => LedgerEntry.fromCache(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCachedEntries(List<LedgerEntry> entries) async {
    try {
      await _storage.write(
        key: _kCachedEntries,
        value: jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Sem espaço ou sem cofre: o app segue com o que a API devolver.
    }
  }

  /// Árvore do planejamento: categorias, subcategorias e metas.
  /// Devolve `null` quando o usuário ainda não mexeu, para o app usar o padrão.
  Future<List<BudgetNode>?> loadBudgetTree() async {
    try {
      final raw = await _storage.read(key: _kBudgetTree);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final nodes = decoded
          .map((e) => BudgetNode.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return nodes.isEmpty ? null : nodes;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBudgetTree(List<BudgetNode> nodes) async {
    try {
      await _storage.write(
        key: _kBudgetTree,
        value: jsonEncode(nodes.map((n) => n.toJson()).toList()),
      );
    } catch (_) {
      // Sem cofre disponível o planejamento vale só na sessão atual.
    }
  }

  /// Se o planejamento mudou neste aparelho e a nuvem ainda não recebeu.
  ///
  /// Enquanto estiver marcado, a árvore que vem da nuvem é mais velha que a
  /// daqui e não pode substituí-la — era assim que uma subcategoria recém
  /// criada sumia na sincronização seguinte.
  Future<bool> loadBudgetPending() async {
    try {
      return (await _storage.read(key: _kBudgetPending)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> saveBudgetPending(bool value) async {
    try {
      if (!value) {
        await _storage.delete(key: _kBudgetPending);
        return;
      }
      await _storage.write(key: _kBudgetPending, value: 'true');
    } catch (_) {
      // Sem cofre, a marca vale só enquanto o app estiver aberto.
    }
  }

  /// Gasto mensal necessário para manter o nível do cartão, em dólar.
  /// A Bybit não expõe esse valor pela API, então ele fica editável.
  Future<double?> loadCardGoal() async {
    try {
      final raw = await _storage.read(key: _kCardGoal);
      if (raw == null || raw.isEmpty) return null;
      return double.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCardGoal(double value) async {
    try {
      await _storage.write(key: _kCardGoal, value: '$value');
    } catch (_) {
      // Sem cofre disponível a meta volta ao padrão na próxima abertura.
    }
  }

  static const _kPendingCard = 'pending_card';

  /// Compras pendentes do cartão, guardadas só neste aparelho.
  ///
  /// Voltam na próxima abertura para o app não perder de vista uma compra que
  /// ainda vai liquidar — e, com ela, o nome que você tenha dado a ela.
  Future<({List<LedgerEntry> visiveis, List<LedgerEntry> aguardando})>
      loadPendingCard() async {
    List<LedgerEntry> lista(dynamic bruto) => bruto is List
        ? bruto
            .whereType<Map>()
            .map((e) => LedgerEntry.fromCache(Map<String, dynamic>.from(e)))
            .toList()
        : const [];

    try {
      final raw = await _storage.read(key: _kPendingCard);
      if (raw == null || raw.isEmpty) {
        return (visiveis: <LedgerEntry>[], aguardando: <LedgerEntry>[]);
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (
        visiveis: lista(decoded['visiveis']),
        aguardando: lista(decoded['aguardando']),
      );
    } catch (_) {
      return (visiveis: <LedgerEntry>[], aguardando: <LedgerEntry>[]);
    }
  }

  Future<void> savePendingCard(
    List<LedgerEntry> visiveis,
    List<LedgerEntry> aguardando,
  ) async {
    try {
      if (visiveis.isEmpty && aguardando.isEmpty) {
        await _storage.delete(key: _kPendingCard);
        return;
      }
      await _storage.write(
        key: _kPendingCard,
        value: jsonEncode({
          'visiveis': visiveis.map((e) => e.toJson()).toList(),
          'aguardando': aguardando.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Sem cofre, as pendentes voltam na próxima atualização.
    }
  }

  /// Assinaturas cadastradas à mão, para o que não passa pelo cartão.
  Future<List<ManualSubscription>> loadManualSubscriptions() async {
    try {
      final raw = await _storage.read(key: _kManualSubscriptions);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((e) => ManualSubscription.fromJson(Map<String, dynamic>.from(e)))
          .whereType<ManualSubscription>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveManualSubscriptions(List<ManualSubscription> assinaturas) async {
    try {
      if (assinaturas.isEmpty) {
        await _storage.delete(key: _kManualSubscriptions);
        return;
      }
      await _storage.write(
        key: _kManualSubscriptions,
        value: jsonEncode(assinaturas.map((m) => m.toJson()).toList()),
      );
    } catch (_) {
      // Sem cofre disponível o cadastro vale só na sessão atual.
    }
  }

  /// Assinaturas marcadas como canceladas, pela chave.
  Future<Set<String>> loadCancelledSubscriptions() async {
    try {
      final raw = await _storage.read(key: _kCancelledSubscriptions);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCancelledSubscriptions(Set<String> chaves) async {
    try {
      if (chaves.isEmpty) {
        await _storage.delete(key: _kCancelledSubscriptions);
        return;
      }
      await _storage.write(
        key: _kCancelledSubscriptions,
        value: jsonEncode(chaves.toList()),
      );
    } catch (_) {
      // Sem cofre disponível a marcação vale só na sessão atual.
    }
  }

  /// Lançamentos que o usuário tirou das contas, por identificador.
  Future<Set<String>> loadHiddenEntries() async {
    try {
      final raw = await _storage.read(key: _kHiddenEntries);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveHiddenEntries(Set<String> ids) async {
    try {
      if (ids.isEmpty) {
        await _storage.delete(key: _kHiddenEntries);
        return;
      }
      await _storage.write(key: _kHiddenEntries, value: jsonEncode(ids.toList()));
    } catch (_) {
      // Sem cofre disponível a escolha vale só enquanto o app estiver aberto.
    }
  }

  Future<Map<String, String>> _loadMap(String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveMap(String key, Map<String, String> value) async {
    try {
      if (value.isEmpty) {
        await _storage.delete(key: key);
        return;
      }
      await _storage.write(key: key, value: jsonEncode(value));
    } catch (_) {
      // Sem cofre disponível a correção vale só enquanto o app estiver aberto.
    }
  }
}
