import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/statement_page.dart';
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
    EditableText.debugDeterministicCursor = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  LedgerEntry compra(String id, String merch, double valor, DateTime quando) =>
      LedgerEntry.fromCardTransaction({
        'transactionId': id,
        'side': '1',
        'transactionDate': '${quando.millisecondsSinceEpoch}',
        'transactionAmount': '$valor',
        'basicCurrency': 'BRL',
        'merchName': merch,
      });

  Future<AppState> abrirExtrato(WidgetTester tester) async {
    final state = AppState()
      ..phase = LoadPhase.ready
      ..seedEntries([
        compra('s1', 'SPOTIFY', 31.90, DateTime(2026, 9, 2, 14)),
        compra('s2', 'SPOTIFY', 31.90, DateTime(2026, 8, 2, 14)),
        compra('s3', 'SPOTIFY', 31.90, DateTime(2026, 7, 2, 14)),
        compra('m1', 'MERCADINHO DO TICO', 35, DateTime(2026, 9, 5, 14)),
      ])
      ..selectMonth(DateTime(2026, 9));

    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state,
            builder: (_, __) => StatementPage(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  group('Total no fim do extrato', () {
    testWidgets('soma o que está na lista do mês', (tester) async {
      await abrirExtrato(tester);

      await tester.ensureVisible(find.text('Total'));
      expect(find.text('2 lançamentos'), findsOneWidget);
      expect(find.text('Fim do extrato'), findsOneWidget);
    });

    testWidgets('buscando uma conta em todos os meses, soma o histórico dela',
        (tester) async {
      final state = await abrirExtrato(tester);

      state.setSearch('spotify');
      await tester.pumpAndSettle();
      expect(find.text('1 lançamento'), findsOneWidget);

      // Liga "todos os meses".
      await tester.tap(find.byIcon(Icons.all_inclusive_rounded));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Total'));
      expect(find.text('3 lançamentos'), findsOneWidget);
      expect(find.text('MERCADINHO DO TICO'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
