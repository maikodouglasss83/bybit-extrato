import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  /// Autorização como vem do registro de ativos do cartão.
  LedgerEntry autorizacao(
    String id,
    String merch,
    double valor,
    DateTime quando, {
    bool concluida = false,
  }) =>
      LedgerEntry.fromCardAuthorization({
        'txnId': id,
        'side': '1',
        'status': '1',
        'tradeStatus': concluida ? '1' : '0',
        'basicAmount': '$valor',
        'basicCurrency': 'BRL',
        'txnCreate': quando.millisecondsSinceEpoch,
        'merchName': merch,
      });

  /// Liquidação como vem do histórico de pontos: com a hora da confirmação.
  LedgerEntry liquidacao(String id, String merch, double valor, DateTime quando) =>
      LedgerEntry.fromCardTransaction({
        'transactionId': id,
        'side': '1',
        'transactionDate': '${quando.millisecondsSinceEpoch}',
        'transactionAmount': '$valor',
        'basicCurrency': 'BRL',
        'merchName': merch,
      });

  group('Data da compra depois de liquidar', () {
    test('a compra vista pendente fica no dia em que o cartão passou', () {
      // Autorizada no dia 12 e confirmada só no dia 13, como o Bilhete Único.
      final passou = DateTime(2026, 9, 12, 14, 4);
      final confirmou = DateTime(2026, 9, 13, 21, 1);

      final state = AppState()
        ..seedPending([autorizacao('ctx-1', 'BILHUNICO', 50, passou)]);
      expect(state.cardEntries.single.time, passou);

      // A liquidação chega e a pendente sai da lista.
      state
        ..seedEntries([liquidacao('cpr-1', 'BILHUNICO', 50, confirmou)])
        ..seedPending(const []);

      final compra = state.cardEntries.single;
      expect(compra.id, 'card-cpr-1');
      expect(compra.pending, isFalse);
      expect(compra.time, passou);
    });

    test('mesmo sem ter visto pendente, a autorização concluída corrige', () {
      final passou = DateTime(2026, 9, 12, 14, 4);
      final confirmou = DateTime(2026, 9, 13, 21, 1);

      final state = AppState()
        ..seedEntries([liquidacao('cpr-1', 'BILHUNICO', 50, confirmou)])
        ..seedPending(
          const [],
          concluidas: [
            autorizacao('ctx-1', 'BILHUNICO', 50, passou, concluida: true),
          ],
        );

      expect(state.cardEntries, hasLength(1));
      expect(state.cardEntries.single.time, passou);
      expect(state.pendingCardCount, 0);
    });

    test('compra do fim do mês confirmada no mês seguinte fica no mês dela',
        () {
      final passou = DateTime(2026, 8, 31, 22);
      final confirmou = DateTime(2026, 9, 1, 10);

      final state = AppState()
        ..seedEntries([liquidacao('cpr-1', 'LOJA X', 99, confirmou)])
        ..seedPending(
          const [],
          concluidas: [autorizacao('ctx-1', 'LOJA X', 99, passou, concluida: true)],
        );

      expect(state.cardSpentInMonth(DateTime(2026, 8)), closeTo(99, 0.001));
      expect(state.cardSpentInMonth(DateTime(2026, 9)), 0);
    });

    test('passagens iguais na mesma semana ficam cada uma no seu dia', () {
      final primeira = DateTime(2026, 9, 8, 7);
      final segunda = DateTime(2026, 9, 10, 7);

      final state = AppState()
        ..seedEntries([
          liquidacao('cpr-2', 'BILHUNICO', 50, DateTime(2026, 9, 11, 20)),
          liquidacao('cpr-1', 'BILHUNICO', 50, DateTime(2026, 9, 9, 20)),
        ])
        ..seedPending(
          const [],
          concluidas: [
            autorizacao('ctx-2', 'BILHUNICO', 50, segunda, concluida: true),
            autorizacao('ctx-1', 'BILHUNICO', 50, primeira, concluida: true),
          ],
        );

      final porId = {for (final e in state.cardEntries) e.id: e.time};
      expect(porId['card-cpr-1'], primeira);
      expect(porId['card-cpr-2'], segunda);

      // Atualizar de novo não embaralha o que já foi acertado.
      state.seedPending(
        const [],
        concluidas: [
          autorizacao('ctx-1', 'BILHUNICO', 50, primeira, concluida: true),
          autorizacao('ctx-2', 'BILHUNICO', 50, segunda, concluida: true),
        ],
      );
      final denovo = {for (final e in state.cardEntries) e.id: e.time};
      expect(denovo, porId);
    });

    test('sem autorização conhecida, a data da Bybit continua valendo', () {
      final confirmou = DateTime(2026, 9, 13, 21, 1);
      final state = AppState()
        ..seedEntries([liquidacao('cpr-1', 'BILHUNICO', 50, confirmou)])
        ..seedPending(const []);

      expect(state.cardEntries.single.time, confirmou);
    });
  });
}
