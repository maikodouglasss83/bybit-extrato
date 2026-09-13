import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/categories_page.dart';
import 'package:bybit_extrato/ui/planning_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  final setembro = DateTime(2026, 9, 10, 14);

  LedgerEntry compra(String id, String merch, double valor) =>
      LedgerEntry.fromCardTransaction({
        'transactionId': id,
        'side': '1',
        'transactionDate': '${setembro.millisecondsSinceEpoch}',
        'transactionAmount': '$valor',
        'basicCurrency': 'BRL',
        'merchName': merch,
      });

  Future<AppState> montar(
    WidgetTester tester,
    Widget Function(AppState) pagina,
    Size tamanho,
  ) async {
    final state = AppState()
      ..phase = LoadPhase.ready
      ..seedEntries([
        compra('n', 'NETFLIX.COM', 20.90),
        compra('m', 'MERCADINHO DO TICO', 35),
      ])
      ..selectMonth(setembro);

    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state,
            builder: (_, __) => pagina(state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  const computador = Size(1400, 1600);

  group('Painel lateral no computador', () {
    testWidgets('gastos por categoria abrem à direita, sem folha',
        (tester) async {
      await montar(tester, (s) => CategoriesPage(state: s), computador);

      await tocar(tester, find.text('Lazer').last);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byTooltip('Fechar'), findsOneWidget);
      expect(find.text('NETFLIX.COM'), findsOneWidget);
      // O painel fica à direita da lista.
      expect(
        tester.getCenter(find.text('NETFLIX.COM')).dx,
        greaterThan(1400 - 360),
      );

      // Outra categoria troca o conteúdo no mesmo painel.
      await tocar(tester, find.text('Alimentação').last);
      expect(find.byTooltip('Fechar'), findsOneWidget);
      expect(find.text('MERCADINHO DO TICO'), findsOneWidget);
      expect(find.text('NETFLIX.COM'), findsNothing);

      await tocar(tester, find.byTooltip('Fechar'));
      expect(find.text('MERCADINHO DO TICO'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('subcategoria do planejamento abre à direita, sem folha',
        (tester) async {
      await montar(tester, (s) => PlanningPage(state: s), computador);

      await tocar(tester, find.text('Lazer'));
      await tocar(tester, find.text('Assinaturas'));

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byTooltip('Fechar'), findsOneWidget);
      expect(find.text('NETFLIX.COM'), findsOneWidget);
      expect(
        tester.getCenter(find.text('NETFLIX.COM')).dx,
        greaterThan(1400 - 360),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no celular continua abrindo a folha de baixo',
        (tester) async {
      await montar(
          tester, (s) => CategoriesPage(state: s), const Size(600, 1600));

      await tocar(tester, find.text('Lazer').last);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byTooltip('Fechar'), findsNothing);
    });
  });
}
