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
    EditableText.debugDeterministicCursor = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  LedgerEntry compra(String id, String merch, double valor) =>
      LedgerEntry.fromCardTransaction({
        'transactionId': id,
        'side': '1',
        'transactionDate': '${DateTime.now().millisecondsSinceEpoch}',
        'transactionAmount': '$valor',
        'basicCurrency': 'BRL',
        'merchName': merch,
      });

  /// O app inteiro, no computador, já na página pedida.
  Future<AppState> abrir(WidgetTester tester, String pagina) async {
    final state = AppState()
      ..phase = LoadPhase.ready
      ..seedEntries([compra('m', 'MERCADINHO DO TICO', 35)]);
    await state.addManualSubscription(name: 'Academia', monthlyBrl: 149.90);

    tester.view.physicalSize = const Size(1440, 900);
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

    await tester.tap(find.widgetWithText(InkWell, pagina).first);
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    // O formulário no painel pode ser mais alto que ele: rola até o botão.
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  final painelAberto = find.byTooltip('Fechar');

  group('Tudo abre ao lado no computador', () {
    testWidgets('assinatura: menu e formulário no painel, Salvar fecha',
        (tester) async {
      final state = await abrir(tester, 'Assinaturas');

      await tocar(tester, find.text('Academia').first);
      expect(find.byType(BottomSheet), findsNothing);
      expect(painelAberto, findsOneWidget);
      expect(find.text('Marcar como cancelada'), findsOneWidget);

      // Sem nada por baixo, não há para onde voltar.
      expect(find.byTooltip('Voltar'), findsNothing);

      // Editar entra por cima do menu, no mesmo painel, com a seta de voltar.
      await tocar(tester, find.text('Editar'));
      expect(find.byType(BottomSheet), findsNothing);
      expect(painelAberto, findsOneWidget);
      expect(find.byTooltip('Voltar'), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);

      // Salvar volta para o menu, em vez de fechar tudo.
      await tocar(tester, find.text('Salvar'));
      expect(painelAberto, findsOneWidget);
      expect(find.text('Marcar como cancelada'), findsOneWidget);
      expect(find.byTooltip('Voltar'), findsNothing);
      // Sem cotação carregada, salvar sem mexer não pode zerar o valor.
      expect(state.manualSubscriptions.single.monthlyBrl, closeTo(149.90, 0.001));
      expect(tester.takeException(), isNull);
    });

    testWidgets('extrato: detalhes, editor e Cancelar no mesmo painel',
        (tester) async {
      await abrir(tester, 'Extrato');

      await tocar(tester, find.text('MERCADINHO DO TICO').first);
      expect(find.byType(BottomSheet), findsNothing);
      expect(painelAberto, findsOneWidget);
      expect(find.text('Detalhes'), findsOneWidget);
      // Com o painel aberto a tabela continua tabela, só mais enxuta.
      expect(find.text('DESCRIÇÃO'), findsOneWidget);

      // O lápis põe o editor por cima dos detalhes, sem abrir folha.
      await tocar(tester, find.byTooltip('Editar nome e categoria'));
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Editar compra'), findsOneWidget);
      expect(find.byTooltip('Voltar'), findsOneWidget);

      // A seta volta para os detalhes.
      await tocar(tester, find.byTooltip('Voltar'));
      expect(find.text('Detalhes'), findsOneWidget);
      expect(find.text('Editar compra'), findsNothing);
      expect(find.byTooltip('Voltar'), findsNothing);

      // Cancelar no editor também volta, em vez de fechar tudo.
      await tocar(tester, find.byTooltip('Editar nome e categoria'));
      await tocar(tester, find.text('Cancelar'));
      expect(painelAberto, findsOneWidget);
      expect(find.text('Detalhes'), findsOneWidget);

      // Tocar de novo na mesma linha fecha; outra vez, abre.
      await tocar(tester, find.text('MERCADINHO DO TICO').first);
      expect(painelAberto, findsNothing);
      await tocar(tester, find.text('MERCADINHO DO TICO').first);
      expect(painelAberto, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('trocar de página fecha o painel', (tester) async {
      await abrir(tester, 'Assinaturas');

      await tocar(tester, find.text('Academia').first);
      expect(painelAberto, findsOneWidget);

      await tocar(tester, find.widgetWithText(InkWell, 'Extrato').first);
      expect(painelAberto, findsNothing);
    });
  });
}
