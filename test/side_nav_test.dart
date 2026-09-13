import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/services/cloud_sync.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Conta conectada, sem ir à rede.
class _ContaConectada extends CloudSync {
  @override
  bool get available => true;
  @override
  bool get signedIn => true;
  @override
  String? get userEmail => 'maiko@exemplo.com';
  @override
  String? get userName => 'Maiko Douglas';
  @override
  String? get userAvatar => null;
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

  Future<void> abrirNoComputador(WidgetTester tester, {CloudSync? cloud}) async {
    final state = AppState(cloud: cloud)
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

      // O botão fica no topo, logo antes do título da página.
      final botao = tester.getCenter(find.byTooltip('Recolher menu'));
      final titulo = tester.getCenter(find.text('Visão geral').last);
      expect(botao.dx, lessThan(titulo.dx));
      expect((botao.dy - titulo.dy).abs(), lessThan(12));
      expect(
        tester.getTopLeft(find.byTooltip('Recolher menu')).dx,
        greaterThan(tester.getTopRight(find.text('Extrato Bybit')).dx),
      );

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

    testWidgets('o rodapé mostra o e-mail, esconde a chave e abre os ajustes',
        (tester) async {
      await abrirNoComputador(tester, cloud: _ContaConectada());

      expect(find.text('Maiko Douglas'), findsOneWidget);
      expect(find.text('maiko@exemplo.com'), findsOneWidget);
      expect(find.textContaining('Chave'), findsNothing);

      // O botão do rodapé fica na mesma linha do nome. O menu lateral vem
      // antes da barra do topo na árvore, então é o primeiro dos dois.
      final noRodape = find.byTooltip('Ajustes').first;
      expect(
        (tester.getCenter(noRodape).dy -
                tester.getCenter(find.text('Maiko Douglas')).dy)
            .abs(),
        lessThan(20),
      );

      await tester.tap(noRodape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar ajustes'), findsWidgets);

      // Recolhido, os ajustes continuam a um clique.
      await tester.tap(find.byTooltip('Fechar ajustes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Recolher menu'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ajustes'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
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
