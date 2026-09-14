import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/budget.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/widgets/common.dart';
import 'package:bybit_extrato/ui/widgets/merchant_avatar.dart';
import 'package:bybit_extrato/util/categorizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  LedgerEntry compra(String id, String merch) => LedgerEntry.fromCardTransaction({
        'transactionId': id,
        'side': '1',
        'transactionDate': '${DateTime(2026, 9, 10).millisecondsSinceEpoch}',
        'transactionAmount': '50',
        'basicCurrency': 'BRL',
        'merchName': merch,
      });

  Future<void> mostrar(WidgetTester tester, Widget selo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: Center(child: selo)),
      ),
    );
  }

  /// O ícone esperado para a categoria de uma compra: o da subcategoria que
  /// a recebe no planejamento.
  IconData iconeEsperado(AppState state, LedgerEntry e) =>
      iconForBudgetNode(state.nodeForCategory(state.categoryOf(e))!);

  group('Selo pela categoria', () {
    testWidgets('a compra mostra o ícone da categoria, sem iniciais',
        (tester) async {
      final state = AppState();
      final e = compra('h', 'HASHTAG TREINAMENTOS');
      await mostrar(tester, MerchantAvatar(entry: e, state: state));

      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(iconeEsperado(state, e)), findsOneWidget);
    });

    testWidgets('marca conhecida também vira ícone sem os logos ligados',
        (tester) async {
      final state = AppState()..useOnlineLogos = false;
      final e = compra('n', 'NETFLIX.COM');
      await mostrar(tester, MerchantAvatar(entry: e, state: state));

      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(iconeEsperado(state, e)), findsOneWidget);
    });

    testWidgets('trocar a categoria troca o ícone', (tester) async {
      final state = AppState();
      final e = compra('m', 'LOJA QUALQUER');
      await state.setEntryOverrides(e, category: SpendCategories.mercado);
      await mostrar(tester, MerchantAvatar(entry: e, state: state));

      expect(
        find.byIcon(iconForBudgetNode(
            state.nodeForCategory(SpendCategories.mercado)!)),
        findsOneWidget,
      );
    });

    testWidgets('subcategoria criada usa o ícone do nome e a cor da principal',
        (tester) async {
      final state = AppState();
      await state.addBudgetNode(name: 'Luz', parentId: 'casa');
      final e = compra('l', 'ENEL SP');
      await state.setEntryOverrides(e, category: 'Luz');
      await mostrar(tester, MerchantAvatar(entry: e, state: state));

      final icone = tester.widget<Icon>(find.byType(Icon));
      expect(icone.icon, Icons.lightbulb_outline_rounded);
      expect(icone.color, mainCategoryColor('casa'));
    });

    testWidgets('assinatura cadastrada à mão usa a categoria dela',
        (tester) async {
      final state = AppState();
      await mostrar(
        tester,
        BrandAvatar(name: 'Seguro Celular', state: state, category: 'Seguro'),
      );

      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });
  });

  test('principal criada pelo usuário ganha ícone pelo nome', () {
    const pets = BudgetNode(id: 'user_1', name: 'Pets', sources: ['Pets']);
    expect(iconForBudgetNode(pets), Icons.pets_rounded);
    // As da estrutura padrão continuam com o ícone delas.
    final casa = defaultBudgetTree().firstWhere((n) => n.id == 'casa');
    expect(iconForBudgetNode(casa), mainCategoryIcon('casa'));
  });
}
