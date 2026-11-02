import 'dart:convert';

import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/services/bybit_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Tamanho de página fixo da Bybit neste endpoint.
const _porPagina = 10;

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
  Map<String, dynamic> autorizacao(
    String id,
    String tradeStatus, {
    String side = '1',
    String merch = 'LOJA',
    double valor = 10,
    DateTime? quando,
  }) =>
      {
        'txnId': id,
        'side': side,
        'tradeStatus': tradeStatus,
        'basicAmount': '$valor',
        'basicCurrency': 'BRL',
        'txnCreate': (quando ?? DateTime(2026, 10, 31)).millisecondsSinceEpoch,
        'merchName': merch,
      };

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

  /// Bybit de mentira: pagina de 10 em 10, ignore o que for pedido, e anota
  /// os pedidos em [pedidos].
  MockClient bybit(
    Map<String, List<Map<String, dynamic>>> porStatus, {
    List<Map<String, dynamic>>? pedidos,
    int recusasPorLimite = 0,
  }) {
    var recusas = 0;
    return MockClient((pedido) async {
      if (pedido.url.path.endsWith('/market/time')) {
        return http.Response(
          jsonEncode({'time': DateTime.now().millisecondsSinceEpoch}),
          200,
        );
      }

      final corpo = jsonDecode(pedido.body) as Map<String, dynamic>;
      pedidos?.add(corpo);
      if (recusas++ < recusasPorLimite) {
        return http.Response(
          jsonEncode({'retCode': 10006, 'retMsg': 'limite'}),
          200,
        );
      }

      final todas = porStatus[corpo['statusCode']] ?? const [];
      final inicio = (corpo['page'] as int) * _porPagina - _porPagina;
      return http.Response(
        jsonEncode({
          'retCode': 0,
          'result': {
            'data': todas.skip(inicio).take(_porPagina).toList(),
            'pageSize': _porPagina,
            'totalCount': todas.length,
          },
        }),
        200,
      );
    });
  }

  BybitClient cliente() => BybitClient(
        apiKey: 'chave',
        apiSecret: 'segredo',
        esperaDoLimite: Duration.zero,
      );

  group('Autorizações do cartão', () {
    test('as pendentes vêm de uma consulta e as concluídas de outra', () async {
      final pedidos = <Map<String, dynamic>>[];
      final mock = bybit({
        '0': [autorizacao('ctx-pendente', '0')],
        '1': [autorizacao('ctx-concluida', '1')],
      }, pedidos: pedidos);

      final pendentes = await http.runWithClient(
        () => cliente().cardPendingAuthorizations(),
        () => mock,
      );
      final concluidas = await http.runWithClient(
        () => cliente().cardCompletedAuthorizations(page: 1),
        () => mock,
      );

      expect(pedidos.map((p) => p['statusCode']), ['0', '1']);
      expect(pendentes.single.id, 'card-auth-ctx-pendente');
      expect(concluidas.entries.single.id, 'card-auth-ctx-concluida');
    });

    test('estornos e reversões ficam de fora das concluídas', () async {
      final lote = await http.runWithClient(
        () => cliente().cardCompletedAuthorizations(page: 1),
        () => bybit({
          '1': [
            autorizacao('ctx-1', '1'),
            autorizacao('ctx-estorno', '1', side: '2'),
            autorizacao('ctx-revertida', '3'),
          ],
        }),
      );

      expect(lote.entries.map((e) => e.id), ['card-auth-ctx-1']);
    });

    test('o fim vem do tamanho que a Bybit respondeu', () async {
      final mock = bybit({
        '1': [for (var i = 0; i < 11; i++) autorizacao('ctx-$i', '1')],
      });

      final primeira = await http.runWithClient(
        () => cliente().cardCompletedAuthorizations(page: 1),
        () => mock,
      );
      final segunda = await http.runWithClient(
        () => cliente().cardCompletedAuthorizations(page: 2),
        () => mock,
      );

      expect(primeira.entries, hasLength(10));
      expect(primeira.temMais, isTrue);
      expect(segunda.entries, hasLength(1));
      expect(segunda.temMais, isFalse);
    });

    test('recusada por excesso de chamadas, tenta de novo', () async {
      final pedidos = <Map<String, dynamic>>[];
      final mock = bybit(
        {
          '1': [autorizacao('ctx-1', '1')],
        },
        pedidos: pedidos,
        recusasPorLimite: 2,
      );
      final lote = await http.runWithClient(
        () => cliente().cardCompletedAuthorizations(page: 1),
        () => mock,
      );

      expect(lote.entries.single.id, 'card-auth-ctx-1');
      expect(pedidos, hasLength(3));
    });

    test('insistindo no excesso, desiste com o erro da Bybit', () {
      expect(
        http.runWithClient(
          () => cliente().cardCompletedAuthorizations(page: 1),
          () => bybit(const {}, recusasPorLimite: 3),
        ),
        throwsA(isA<BybitException>()),
      );
    });
  });

  group('Correção das datas em segundo plano', () {
    final passou = DateTime(2026, 10, 31, 19, 36);
    final confirmou = DateTime(2026, 11, 2, 14, 2);

    /// [quantas] compras diferentes, cada uma com a sua autorização.
    ({List<LedgerEntry> liquidadas, List<Map<String, dynamic>> autorizacoes})
        historico(int quantas) => (
              liquidadas: [
                for (var i = 0; i < quantas; i++)
                  liquidacao('cpr-$i', 'LOJA $i', 10, confirmou),
              ],
              autorizacoes: [
                for (var i = 0; i < quantas; i++)
                  autorizacao('ctx-$i', '1', merch: 'LOJA $i', quando: passou),
              ],
            );

    test('percorre as páginas e põe cada compra no dia dela', () async {
      final h = historico(25);
      final state = AppState()..seedEntries(h.liquidadas);

      await http.runWithClient(
        () => state.corrigirDatasDasCompras(cliente()),
        () => bybit({'1': h.autorizacoes}),
      );

      expect(state.cardEntries, hasLength(25));
      expect(state.cardEntries.every((e) => e.time == passou), isTrue);
    });

    test('depois de ver tudo, para na primeira página sem novidade', () async {
      final h = historico(25);
      final state = AppState()..seedEntries(h.liquidadas);
      final mock = bybit({'1': h.autorizacoes});
      await http.runWithClient(
        () => state.corrigirDatasDasCompras(cliente()),
        () => mock,
      );

      final pedidos = <Map<String, dynamic>>[];
      await http.runWithClient(
        () => state.corrigirDatasDasCompras(cliente()),
        () => bybit({'1': h.autorizacoes}, pedidos: pedidos),
      );

      expect(pedidos, hasLength(1));
    });

    test('retoma de onde parou se a Bybit recusar no meio', () async {
      final h = historico(25);
      final state = AppState()..seedEntries(h.liquidadas);

      // A primeira volta cai na segunda página.
      var chamadas = 0;
      final instavel = MockClient((pedido) async {
        if (pedido.url.path.endsWith('/market/time')) {
          return http.Response(
            jsonEncode({'time': DateTime.now().millisecondsSinceEpoch}),
            200,
          );
        }
        if (++chamadas > 1) {
          return http.Response(
            jsonEncode({'retCode': 10000, 'retMsg': 'fora do ar'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'retCode': 0,
            'result': {
              'data': h.autorizacoes.take(_porPagina).toList(),
              'pageSize': _porPagina,
              'totalCount': h.autorizacoes.length,
            },
          }),
          200,
        );
      });
      await http.runWithClient(
        () => state.corrigirDatasDasCompras(cliente()),
        () => instavel,
      );
      expect(state.cardEntries.where((e) => e.time == passou), hasLength(10));

      final pedidos = <Map<String, dynamic>>[];
      await http.runWithClient(
        () => state.corrigirDatasDasCompras(cliente()),
        () => bybit({'1': h.autorizacoes}, pedidos: pedidos),
      );

      expect(state.cardEntries.every((e) => e.time == passou), isTrue);
      expect(pedidos.map((p) => p['page']), [1, 2, 3]);
    });

    test('valor um pouco diferente na liquidação ainda é a mesma compra', () {
      // Estimativa de 13,26 autorizada e 12,41 liquidado, como no Uber.
      final state = AppState()
        ..seedEntries([liquidacao('cpr-1', 'LOJA', 12.41, confirmou)])
        ..seedPending(
          const [],
          concluidas: [
            LedgerEntry.fromCardAuthorization(
              autorizacao('ctx-1', '1', valor: 13.26, quando: passou),
            ),
          ],
        );

      expect(state.cardEntries.single.time, passou);
    });

    test('valor bem diferente não é a mesma compra', () {
      final state = AppState()
        ..seedEntries([liquidacao('cpr-1', 'LOJA', 50, confirmou)])
        ..seedPending(
          const [],
          concluidas: [
            LedgerEntry.fromCardAuthorization(
              autorizacao('ctx-1', '1', valor: 100, quando: passou),
            ),
          ],
        );

      expect(state.cardEntries.single.time, confirmou);
    });

    test('o valor igual tem prioridade sobre o parecido', () {
      final parecida = DateTime(2026, 10, 31, 10);
      final exata = DateTime(2026, 10, 31, 20);

      final state = AppState()
        ..seedEntries([liquidacao('cpr-1', 'LOJA', 10, confirmou)])
        ..seedPending(
          const [],
          concluidas: [
            LedgerEntry.fromCardAuthorization(
              autorizacao('ctx-1', '1', valor: 11, quando: parecida),
            ),
            LedgerEntry.fromCardAuthorization(
              autorizacao('ctx-2', '1', valor: 10, quando: exata),
            ),
          ],
        );

      expect(state.cardEntries.single.time, exata);
    });

    test('a pendente de valor parecido continua pendente', () {
      final state = AppState()
        ..seedEntries([liquidacao('cpr-1', 'LOJA', 12, confirmou)])
        ..seedPending([
          LedgerEntry.fromCardAuthorization(
            autorizacao('ctx-1', '0', valor: 13, quando: passou),
          ),
        ]);

      expect(state.pendingCardCount, 1);
      expect(
        state.cardEntries.firstWhere((e) => !e.pending).time,
        confirmou,
      );
    });
  });
}
