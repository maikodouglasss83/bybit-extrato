import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/budget.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/services/cloud_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Nuvem em memória, com a opção de recusar envios como numa queda de rede.
class _NuvemFalsa extends CloudSync {
  final Map<String, dynamic> ajustes = {};
  bool recusarEnvios = false;

  @override
  bool get available => true;

  @override
  bool get signedIn => true;

  @override
  Future<Map<String, dynamic>> pullPreferences() async => Map.of(ajustes);

  @override
  Future<void> pushPreference(String chave, dynamic valor) async {
    if (recusarEnvios) throw Exception('sem rede');
    ajustes[chave] = valor;
  }

  @override
  Future<List<LedgerEntry>> pullEntries() async => const [];

  @override
  Future<void> pushEntries(List<LedgerEntry> entries) async {}
}

List<String> _nomesNaNuvem(_NuvemFalsa nuvem) =>
    (nuvem.ajustes['budget_tree'] as List)
        .map((n) => (n as Map)['name'].toString())
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  group('Subcategoria nova e a nuvem', () {
    test('não some quando o envio falha e a nuvem ainda tem a árvore velha',
        () async {
      final nuvem = _NuvemFalsa()
        ..ajustes['budget_tree'] =
            defaultBudgetTree().map((n) => n.toJson()).toList();
      final state = AppState(cloud: nuvem);

      nuvem.recusarEnvios = true;
      final erro = await state.addBudgetNode(name: 'Luz', parentId: 'casa');
      expect(erro, isNull);

      // A rede volta e o app sincroniza: antes, a árvore da nuvem apagava a Luz.
      nuvem.recusarEnvios = false;
      await state.syncWithCloud();

      expect(state.budgetNodes.map((n) => n.name), contains('Luz'));
      expect(_nomesNaNuvem(nuvem), contains('Luz'));
    });

    test('depois de enviada, a nuvem volta a valer normalmente', () async {
      final nuvem = _NuvemFalsa();
      final state = AppState(cloud: nuvem);

      await state.addBudgetNode(name: 'Luz', parentId: 'casa');
      await Future<void>.delayed(Duration.zero);
      expect(_nomesNaNuvem(nuvem), contains('Luz'));

      // Outro aparelho apagou a Luz: sem nada pendente aqui, isso vale.
      nuvem.ajustes['budget_tree'] =
          defaultBudgetTree().map((n) => n.toJson()).toList();
      await state.syncWithCloud();

      expect(state.budgetNodes.map((n) => n.name), isNot(contains('Luz')));
    });

    test('planejamento de outro aparelho chega quando nada mudou aqui',
        () async {
      final nuvem = _NuvemFalsa()
        ..ajustes['budget_tree'] = [
          ...defaultBudgetTree().map((n) => n.toJson()),
          const BudgetNode(
            id: 'user_1',
            name: 'Água',
            parentId: 'casa',
            sources: ['Água'],
          ).toJson(),
        ];
      final state = AppState(cloud: nuvem);

      await state.syncWithCloud();

      expect(state.budgetNodes.map((n) => n.name), contains('Água'));
    });
  });
}
