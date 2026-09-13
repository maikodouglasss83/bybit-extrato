import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/connect_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  Future<void> montar(WidgetTester tester, Widget tela, Size tamanho) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: tela),
      ),
    );
    await tester.pump();
  }

  ApiKeyInfo chave({
    required Duration venceEm,
    int readOnly = 1,
    List<String> cartao = const ['BitCard'],
  }) =>
      ApiKeyInfo.fromJson({
        'note': 'APP Claude',
        'readOnly': readOnly,
        'permissions': {
          'Wallet': ['AccountTransfer'],
          'BitCard': cartao,
        },
        'ips': ['*'],
        'expiredAt': DateTime.now().add(venceEm).toUtc().toIso8601String(),
      });

  group('Tela de conexão', () {
    testWidgets('no computador o formulário fica ao lado do passo a passo',
        (tester) async {
      await montar(tester, ConnectPage(state: AppState()), const Size(1440, 900));

      expect(find.text('Passo a passo'), findsOneWidget);
      expect(find.text('Colar'), findsNWidgets(2));
      expect(find.text('Somente leitura'), findsOneWidget);

      // Lado a lado: o passo a passo começa à direita do formulário.
      final formulario = tester.getTopLeft(find.text('API Key'));
      final passos = tester.getTopLeft(find.text('Passo a passo'));
      expect(passos.dx, greaterThan(formulario.dx + 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no celular o passo a passo vem depois do formulário',
        (tester) async {
      await montar(tester, ConnectPage(state: AppState()), const Size(390, 844));

      final botao = tester.getTopLeft(find.text('Conectar'));
      final passos = tester.getTopLeft(find.text('Passo a passo'));
      expect(passos.dy, greaterThan(botao.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Conectar só libera com a chave e o secret preenchidos',
        (tester) async {
      await montar(tester, ConnectPage(state: AppState()), const Size(1440, 900));

      FilledButton botao() =>
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Conectar'));

      expect(botao().onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'minha-chave');
      await tester.pump();
      expect(botao().onPressed, isNull); // falta o secret

      await tester.enterText(find.byType(TextField).at(1), 'meu-secret');
      await tester.pump();
      expect(botao().onPressed, isNotNull);
    });
  });

  group('Situação da chave', () {
    testWidgets('mostra somente leitura e quando vence', (tester) async {
      final state = AppState()
        ..apiKeyInfo = chave(venceEm: const Duration(days: 57, hours: 1));

      await montar(tester, KeyStatusCard(state: state), const Size(600, 400));

      expect(find.text('Somente leitura · APP Claude'), findsOneWidget);
      expect(find.textContaining('Vence em 57 dias'), findsOneWidget);
      expect(find.textContaining('permissão do cartão'), findsNothing);
    });

    testWidgets('avisa quando falta a permissão do cartão', (tester) async {
      final state = AppState()
        ..apiKeyInfo = chave(venceEm: const Duration(days: 57), cartao: const []);

      await montar(tester, KeyStatusCard(state: state), const Size(600, 400));

      expect(find.textContaining('permissão do cartão'), findsOneWidget);
    });

    testWidgets('o aviso de vencimento só aparece nas duas últimas semanas',
        (tester) async {
      final state = AppState()
        ..apiKeyInfo = chave(venceEm: const Duration(days: 40));

      await montar(tester, KeyExpiryBanner(state: state), const Size(600, 200));
      expect(find.text('Trocar chave'), findsNothing);

      state.apiKeyInfo = chave(venceEm: const Duration(days: 5, hours: 1));
      await montar(tester, KeyExpiryBanner(state: state), const Size(600, 200));

      expect(find.text('Trocar chave'), findsOneWidget);
      expect(find.textContaining('vence em 5 dias'), findsOneWidget);
    });

    testWidgets('chave vencida pede para criar outra', (tester) async {
      final state = AppState()
        ..apiKeyInfo = chave(venceEm: const Duration(days: -2));

      await montar(tester, KeyExpiryBanner(state: state), const Size(600, 200));

      expect(find.textContaining('venceu'), findsOneWidget);
      expect(find.text('Trocar chave'), findsOneWidget);
    });
  });
}
