import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/dashboard_page.dart';
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

  LedgerEntry compra({String pan4 = '4469'}) =>
      LedgerEntry.fromCardTransaction({
        'transactionId': 'c1',
        'side': '1',
        'transactionDate': '${DateTime.now().millisecondsSinceEpoch}',
        'transactionAmount': '21.99',
        'basicCurrency': 'BRL',
        'merchName': 'MERCADO FLAMENGO',
        'pan4': pan4,
      });

  Future<AppState> abrirResumo(
    WidgetTester tester, {
    required List<LedgerEntry> compras,
    VoidCallback? onSeeCategories,
  }) async {
    final state = AppState()
      ..phase = LoadPhase.ready
      ..seedEntries(compras);

    // Mais larga que um celular: a fonte de teste desenha cada letra como um
    // quadrado, e num 390 real caberia o que aqui não cabe.
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state,
            builder: (_, __) => DashboardPage(
              state: state,
              onSeeStatement: () {},
              onSeeCategories: onSeeCategories ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  group('Cartão no topo do resumo', () {
    testWidgets('mostra o nome e os últimos dígitos das compras',
        (tester) async {
      final state = await abrirResumo(tester, compras: [compra()]);

      expect(state.cardLast4, '4469');
      expect(find.text('BYBIT CARD'), findsOneWidget);
      expect(find.text('•••• 4469'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem dígitos conhecidos, diz que o cartão está conectado',
        (tester) async {
      await abrirResumo(tester, compras: [compra(pan4: '')]);

      expect(find.text('Cartão conectado'), findsOneWidget);
    });

    testWidgets('o atalho do cartão abre os gastos por categoria',
        (tester) async {
      var abriu = false;
      await abrirResumo(
        tester,
        compras: [compra()],
        onSeeCategories: () => abriu = true,
      );

      await tester.tap(find.text('Ver gastos'));
      await tester.pumpAndSettle();
      expect(abriu, isTrue);
    });
  });
}
