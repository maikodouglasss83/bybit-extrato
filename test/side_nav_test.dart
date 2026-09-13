import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/shell.dart';
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

  Future<void> abrirNoComputador(WidgetTester tester) async {
    final state = AppState()
      ..phase = LoadPhase.ready
      ..seedEntries(<LedgerEntry>[]);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: AnimatedBuilder(
          animation: state,
          builder: (_, __) => AppShell(
            state: state,
            themeMode: ThemeMode.dark,
            onThemeModeChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Menu lateral no computador', () {
    testWidgets('recolhe para só os ícones e expande de volta', (tester) async {
      await abrirNoComputador(tester);

      expect(find.text('Extrato Bybit'), findsOneWidget);
      expect(find.text('Gastos por categoria'), findsOneWidget);

      await tester.tap(find.byTooltip('Recolher menu'));
      await tester.pumpAndSettle();

      expect(find.text('Extrato Bybit'), findsNothing);
      expect(find.text('Gastos por categoria'), findsNothing);
      expect(find.text('GERAL'), findsNothing);
      // Os ícones continuam navegando.
      await tester.tap(find.byIcon(Icons.receipt_long_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Extrato'), findsWidgets);

      await tester.tap(find.byTooltip('Expandir menu'));
      await tester.pumpAndSettle();
      expect(find.text('Gastos por categoria'), findsOneWidget);
    });

    testWidgets('não estoura enquanto anima', (tester) async {
      await abrirNoComputador(tester);

      await tester.tap(find.byTooltip('Recolher menu'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expandir menu'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
