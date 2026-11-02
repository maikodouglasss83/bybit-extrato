import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/services/cloud_sync.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/statement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Tabela de transações de mentira, compartilhada entre "aparelhos".
class _Nuvem extends CloudSync {
  _Nuvem([Map<String, LedgerEntry>? linhas]) : linhas = linhas ?? {};

  final Map<String, LedgerEntry> linhas;
  final Map<String, dynamic> ajustes = {};
  bool foraDoAr = false;

  void _exigirRede() {
    if (foraDoAr) throw Exception('sem rede');
  }

  @override
  bool get available => true;
  @override
  bool get signedIn => true;

  @override
  Future<List<LedgerEntry>> pullEntries() async => linhas.values.toList();
  @override
  Future<List<LedgerEntry>> pullManualEntries() async =>
      linhas.values.where((e) => e.isManual).toList();
  @override
  Future<Map<String, dynamic>> pullPreferences() async => Map.of(ajustes);

  @override
  Future<void> pushEntries(List<LedgerEntry> entries) async {
    _exigirRede();
    for (final e in entries) {
      linhas[e.id] = e;
    }
  }

  @override
  Future<void> deleteEntries(List<String> ids) async {
    _exigirRede();
    ids.forEach(linhas.remove);
  }

  @override
  Future<void> pushPreference(String chave, dynamic valor) async {
    ajustes[chave] = valor;
  }
}

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

  group('Lançamentos na nuvem', () {
    Future<void> lancar(AppState state, String nome) =>
        state.salvarLancamentoManual(
          nome: nome,
          valorBrl: 80,
          quando: dia,
          categoria: 'Mercado',
        );

    test('cada lançamento vira uma linha da tabela', () async {
      final nuvem = _Nuvem();
      await lancar(AppState(cloud: nuvem), 'Feira');

      expect(nuvem.linhas.values.single.note, 'Feira');
    });

    test('um aparelho sem o lançamento não apaga o do outro', () async {
      final nuvem = _Nuvem();
      await lancar(AppState(cloud: nuvem), 'Feira');

      // Outro aparelho, vazio, atualiza sem nem baixar nada.
      final outro = AppState(cloud: nuvem);
      await outro.syncWithCloud(pushOnly: true);
      expect(nuvem.linhas, hasLength(1));

      await outro.syncWithCloud();
      expect(outro.cardEntries.single.note, 'Feira');
    });

    test('dois aparelhos lançando ao mesmo tempo ficam com os dois', () async {
      final nuvem = _Nuvem();
      final a = AppState(cloud: nuvem);
      final b = AppState(cloud: nuvem);
      await lancar(a, 'Feira');
      await lancar(b, 'Padaria');

      await a.syncWithCloud();
      await b.syncWithCloud();

      expect(a.cardEntries, hasLength(2));
      expect(b.cardEntries, hasLength(2));
    });

    test('sem rede fica na fila e sobe na próxima sincronização', () async {
      final nuvem = _Nuvem()..foraDoAr = true;
      final state = AppState(cloud: nuvem);
      await lancar(state, 'Feira');
      expect(nuvem.linhas, isEmpty);

      // Baixar a nuvem vazia não pode sumir com o que ainda não subiu.
      nuvem.foraDoAr = false;
      await state.syncWithCloud();

      expect(state.cardEntries.single.note, 'Feira');
      expect(nuvem.linhas, hasLength(1));
    });

    test('a exclusão vale nos outros aparelhos', () async {
      final nuvem = _Nuvem();
      final a = AppState(cloud: nuvem);
      await lancar(a, 'Feira');
      final b = AppState(cloud: nuvem);
      await b.syncWithCloud();

      await a.removerLancamentoManual(a.cardEntries.single);
      await b.syncWithCloud();

      expect(nuvem.linhas, isEmpty);
      expect(b.cardEntries, isEmpty);
    });

    test('excluir sem rede não volta ao sincronizar', () async {
      final nuvem = _Nuvem();
      final state = AppState(cloud: nuvem);
      await lancar(state, 'Feira');

      nuvem.foraDoAr = true;
      await state.removerLancamentoManual(state.cardEntries.single);
      nuvem.foraDoAr = false;
      await state.syncWithCloud();

      expect(state.cardEntries, isEmpty);
      expect(nuvem.linhas, isEmpty);
    });

    test('a lista antiga das preferências vira linhas e é esvaziada', () async {
      final antigo = LedgerEntry(
        id: 'manual-1',
        time: dia,
        rawType: 'MANUAL',
        kind: LedgerKind.cardPurchase,
        coin: 'BRL',
        change: -80,
        fee: 0,
        note: 'Feira',
        source: LedgerEntry.fonteManual,
      );
      final nuvem = _Nuvem()
        ..ajustes['manual_entries'] = [antigo.toJson()];

      final state = AppState(cloud: nuvem);
      await state.syncWithCloud();

      expect(state.cardEntries.single.note, 'Feira');
      expect(nuvem.linhas, contains('manual-1'));
      expect(nuvem.ajustes['manual_entries'], isEmpty);
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
