import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
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
    // Sem resposta simulada, gravações no cofre ficariam esperando para
    // sempre dentro do tempo simulado do teste.
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

  Future<AppState> abrirPlanejamento(WidgetTester tester) async {
    final state = AppState()
      ..phase = LoadPhase.ready
      ..seedEntries([
        compra('n', 'NETFLIX.COM', 20.90),
        compra('m', 'MERCADINHO DO TICO', 35),
      ])
      ..selectMonth(setembro);

    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state,
            builder: (_, __) => PlanningPage(state: state),
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

  group('Subcategoria no planejamento', () {
    testWidgets('tocar numa subcategoria abre os gastos dela', (tester) async {
      await abrirPlanejamento(tester);

      await tocar(tester, find.text('Lazer'));
      await tocar(tester, find.text('Assinaturas'));

      // Abre os gastos, e não a meta.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('NETFLIX.COM'), findsOneWidget);
      expect(find.textContaining('1 compra'), findsOneWidget);
      // O gasto de mercado não é desta subcategoria.
      expect(find.text('MERCADINHO DO TICO'), findsNothing);
    });

    testWidgets('a meta continua no menu de três pontos', (tester) async {
      await abrirPlanejamento(tester);

      await tocar(tester, find.text('Lazer'));
      await tocar(tester, find.byIcon(Icons.more_vert_rounded).first);

      expect(find.text('Definir meta'), findsOneWidget);
    });
  });
}
