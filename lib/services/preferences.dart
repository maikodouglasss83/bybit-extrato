import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../budget.dart';
import '../models.dart';

/// Ajustes do usuário que ficam guardados no dispositivo.
///
/// As correções são indexadas pelo nome original do estabelecimento, para que
/// valham também para as próximas compras no mesmo lugar.
class PreferencesStore {
  static const _storage = FlutterSecureStorage();
  static const _kCategoryOverrides = 'category_overrides';
  static const _kNameOverrides = 'name_overrides';
  static const _kFixedOverrides = 'fixed_overrides';
  static const _kHiddenEntries = 'hidden_entries';
  static const _kOnlineLogos = 'online_logos';
  static const _kShowInBrl = 'show_in_brl';
  static const _kSkippedLogin = 'skipped_login';
  static const _kCardGoal = 'card_goal_usd';
  static const _kBudgetTree = 'budget_tree';
  static const _kCachedEntries = 'cached_entries';

  Future<Map<String, String>> loadCategoryOverrides() =>
      _loadMap(_kCategoryOverrides);

  Future<void> saveCategoryOverrides(Map<String, String> overrides) =>
      _saveMap(_kCategoryOverrides, overrides);

  Future<Map<String, String>> loadNameOverrides() => _loadMap(_kNameOverrides);

  Future<void> saveNameOverrides(Map<String, String> overrides) =>
      _saveMap(_kNameOverrides, overrides);

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
