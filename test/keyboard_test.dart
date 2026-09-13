import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/planning_page.dart';
import 'package:bybit_extrato/ui/subscriptions_page.dart';
import 'package:bybit_extrato/ui/widgets/entry_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Altura da tela e de um teclado aberto nela.
///
/// Só a altura importa para o teclado. A largura muda por folha: a fonte de
/// teste desenha cada letra como um quadrado, bem mais largo que no celular, e
/// as telas com mais texto numa linha estourariam só por isso.
const _alturaDaTela = 800.0;
const _teclado = 320.0;

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

  Future<void> montar(
    WidgetTester tester,
    Widget tela, {
    double largura = 390,
  }) async {
    tester.view.physicalSize = Size(largura, _alturaDaTela);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: tela),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Abre o teclado e confere que o botão pode ser alcançado acima dele.
  Future<void> conferirAcimaDoTeclado(WidgetTester tester, Finder botao) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
    await tester.pumpAndSettle();

    await tester.ensureVisible(botao);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(botao).bottom,
      lessThanOrEqualTo(_alturaDaTela - _teclado + 0.5),
      reason: 'o teclado cobriria o botão',
    );
    expect(tester.takeException(), isNull);

    // E o botão responde ao toque ali em cima.
    await tester.tap(botao, warnIfMissed: true);
    await tester.pumpAndSettle();
  }

  group('Folhas com teclado aberto', () {
    testWidgets('nova assinatura sobe acima do teclado', (tester) async {
      final state = AppState()..phase = LoadPhase.ready;
      await montar(tester, SubscriptionsPage(state: state));

      await tester.tap(find.text('Nova assinatura').first);
      await tester.pumpAndSettle();
      expect(find.text('Cadastrar'), findsOneWidget);

      await conferirAcimaDoTeclado(tester, find.text('Cadastrar'));
      // Tocou sem preencher: o aviso aparece, sinal de que o toque chegou.
      expect(find.text('Dê um nome para a assinatura.'), findsOneWidget);
    });

    testWidgets('editar compra sobe acima do teclado', (tester) async {
      final state = AppState()..phase = LoadPhase.ready;
      final compra = LedgerEntry.fromCardTransaction({
        'transactionId': 'c1',
        'side': '1',
        'transactionDate': '${DateTime(2026, 9, 7, 14).millisecondsSinceEpoch}',
        'transactionAmount': '68.61',
        'basicCurrency': 'BRL',
        'merchName': 'ATACADO E AUTO SERVICO',
      });

      await montar(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showEntryEditor(context, state: state, entry: compra),
              child: const Text('abrir'),
            ),
          ),
        ),
        largura: 600,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await conferirAcimaDoTeclado(tester, find.text('Salvar'));
    });

    testWidgets('nova categoria sobe acima do teclado', (tester) async {
      final state = AppState()..phase = LoadPhase.ready;
      await montar(tester, PlanningPage(state: state), largura: 600);

      // O botão fica no fim de uma lista que só constrói o que está à vista:
      // é preciso rolar até ele existir.
      final abrir = find.text('Nova categoria');
      await tester.scrollUntilVisible(
        abrir,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(abrir);
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
      await tester.pumpAndSettle();

      final criar = find.text('Criar');
      await tester.ensureVisible(criar);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(criar).bottom,
        lessThanOrEqualTo(_alturaDaTela - _teclado + 0.5),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
