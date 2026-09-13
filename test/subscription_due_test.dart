import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/subscriptions.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/subscriptions_page.dart';
import 'package:bybit_extrato/util/format.dart';
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

  final hoje = DateTime(2026, 9, 13, 15);

  Subscription assinatura({
    int? dia,
    DateTime? ultima,
    bool cancelada = false,
  }) =>
      Subscription(
        key: 'x',
        name: 'Teste',
        monthlyBrl: 10,
        manual: true,
        cancelled: cancelada,
        dueDay: dia,
        lastCharge: ultima,
      );

  group('Próximo vencimento', () {
    test('dia informado ainda por vir neste mês', () {
      expect(assinatura(dia: 20).proximoVencimento(hoje), DateTime(2026, 9, 20));
    });

    test('dia informado que já passou vai para o mês seguinte', () {
      expect(assinatura(dia: 5).proximoVencimento(hoje), DateTime(2026, 10, 5));
    });

    test('sem dia informado, segue o dia da última cobrança', () {
      // Hashtag: cobrou dia 2 deste mês, a próxima é 2 de outubro.
      expect(
        assinatura(ultima: DateTime(2026, 9, 2)).proximoVencimento(hoje),
        DateTime(2026, 10, 2),
      );
      // TIM: cobrou 23 de agosto, a próxima é 23 de setembro.
      expect(
        assinatura(ultima: DateTime(2026, 8, 23)).proximoVencimento(hoje),
        DateTime(2026, 9, 23),
      );
    });

    test('cobrada hoje, a próxima é no mês que vem', () {
      expect(
        assinatura(ultima: DateTime(2026, 9, 13, 9)).proximoVencimento(hoje),
        DateTime(2026, 10, 13),
      );
    });

    test('vence hoje e ainda não foi cobrada', () {
      final s = assinatura(dia: 13, ultima: DateTime(2026, 8, 13));
      expect(s.proximoVencimento(hoje), DateTime(2026, 9, 13));
      expect(fmtVencimento(s.proximoVencimento(hoje)!, hoje: hoje), 'vence hoje');
    });

    test('dia 31 num mês curto cai no último dia dele', () {
      expect(
        assinatura(dia: 31).proximoVencimento(DateTime(2027, 2, 10)),
        DateTime(2027, 2, 28),
      );
    });

    test('dezembro passa para janeiro do ano seguinte', () {
      expect(
        assinatura(dia: 5).proximoVencimento(DateTime(2026, 12, 20)),
        DateTime(2027, 1, 5),
      );
    });

    test('sem dia conhecido, ou cancelada, não há vencimento', () {
      expect(assinatura().proximoVencimento(hoje), isNull);
      expect(assinatura(dia: 20, cancelada: true).proximoVencimento(hoje), isNull);
    });
  });

  group('Texto do vencimento', () {
    test('hoje, amanhã ou dia e mês', () {
      expect(fmtVencimento(DateTime(2026, 9, 13), hoje: hoje), 'vence hoje');
      expect(fmtVencimento(DateTime(2026, 9, 14), hoje: hoje), 'vence amanhã');
      expect(fmtVencimento(DateTime(2026, 10, 2), hoje: hoje), 'vence 2 out');
      expect(
        fmtVencimento(DateTime(2026, 10, 2), hoje: hoje, comPrefixo: false),
        '2 out',
      );
    });
  });

  testWidgets('a lista mostra quando vence, ou que falta o dia',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState()..phase = LoadPhase.ready;
    await state.addManualSubscription(
      name: 'Academia',
      monthlyBrl: 149.90,
      category: 'Saúde',
      dueDay: 10,
    );
    await state.addManualSubscription(
      name: 'Meli',
      monthlyBrl: 59.90,
      category: 'Streaming',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: SubscriptionsPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    final esperado = fmtVencimento(
      state
          .subscriptions()
          .firstWhere((s) => s.name == 'Academia')
          .proximoVencimento(DateTime.now())!,
    );
    expect(find.text('Saúde · $esperado'), findsOneWidget);
    expect(find.text('Streaming · sem dia de vencimento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
