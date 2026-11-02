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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  final dia = DateTime(2026, 10, 12, 9);
  final mes = DateTime(2026, 10);

  group('Lançamentos manuais', () {
    test('o gasto entra nos totais e na categoria escolhida', () async {
      final state = AppState();
      await state.salvarLancamentoManual(
        nome: 'Feira',
        valorBrl: 80,
        quando: dia,
        categoria: 'Mercado',
      );

      final gasto = state.cardEntries.single;
      expect(gasto.isManual, isTrue);
      expect(gasto.change, -80);
      expect(state.categoryOf(gasto), 'Mercado');
      expect(state.cardSpentInMonth(mes), 80);
    });

    test('a entrada aparece no extrato e não reduz o gasto', () async {
      final state = AppState();
      await state.salvarLancamentoManual(
        nome: 'Feira',
        valorBrl: 80,
        quando: dia,
        categoria: 'Mercado',
      );
      await state.salvarLancamentoManual(
        nome: 'Pix recebido',
        valorBrl: 50,
        quando: dia,
        categoria: 'Outros',
        entrada: true,
      );

      expect(state.entries, hasLength(2));
      expect(state.cardSpentInMonth(mes), 80);
    });

    test('editar substitui, e excluir tira dos totais', () async {
      final state = AppState();
      await state.salvarLancamentoManual(
        nome: 'Feira',
        valorBrl: 80,
        quando: dia,
        categoria: 'Mercado',
      );
      final original = state.cardEntries.single;

      await state.salvarLancamentoManual(
        id: original.id,
        nome: 'Feira do sábado',
        valorBrl: 95,
        quando: DateTime(2026, 9, 5),
        categoria: 'Mercado',
      );

      expect(state.cardEntries, hasLength(1));
      expect(state.versaoAtual(original).note, 'Feira do sábado');
      expect(state.cardSpentInMonth(mes), 0);
      expect(state.cardSpentInMonth(DateTime(2026, 9)), 95);

      await state.removerLancamentoManual(original);
      expect(state.cardEntries, isEmpty);
    });

    test('não vira par de uma autorização da Bybit', () async {
      final state = AppState();
      await state.salvarLancamentoManual(
        nome: 'LOJA',
        valorBrl: 10,
        quando: dia,
        categoria: 'Outros',
      );

      state.seedPending(const [], concluidas: [
        LedgerEntry.fromCardAuthorization({
          'txnId': 'ctx-1',
          'side': '1',
          'tradeStatus': '1',
          'basicAmount': '10',
          'basicCurrency': 'BRL',
          'txnCreate': dia.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          'merchName': 'LOJA',
        }),
      ]);

      expect(state.cardEntries.single.time, dia);
    });

    test('vem de outro aparelho pela nuvem', () async {
      final origem = AppState();
      await origem.salvarLancamentoManual(
        nome: 'Feira',
        valorBrl: 80,
        quando: dia,
        categoria: 'Mercado',
      );

      final outro = AppState()
        ..aplicarAjustesDaNuvem({
          'manual_entries': origem.cardEntries.map((e) => e.toJson()).toList(),
        });

      expect(outro.cardEntries.single.note, 'Feira');
      expect(outro.cardEntries.single.isManual, isTrue);
    });
  });

  testWidgets('o botão do extrato registra um gasto com data de hoje',
      (tester) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState()
      ..phase = LoadPhase.ready
      ..seedEntries(<LedgerEntry>[]);

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

    await tester.tap(find.byTooltip('Novo lançamento'));
    await tester.pumpAndSettle();

    // Sem valor, avisa em vez de salvar.
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Feira');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o valor.'), findsOneWidget);
    expect(state.cardEntries, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Valor'), '1.234,50');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(state.cardEntries.single.change, -1234.5);
    expect(find.text('Salvar'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
