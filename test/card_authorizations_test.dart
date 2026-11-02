import 'dart:convert';

import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/services/bybit_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  /// Autorização como vem do registro de ativos do cartão.
  Map<String, dynamic> autorizacao(
    String id,
    String tradeStatus, {
    String side = '1',
  }) =>
      {
        'txnId': id,
        'side': side,
        'tradeStatus': tradeStatus,
        'basicAmount': '10',
        'basicCurrency': 'BRL',
        'txnCreate': 1793637473000,
        'merchName': 'LOJA',
      };

  /// Consulta as autorizações contra uma Bybit de mentira, que separa as
  /// respostas pelo status pedido, e anota os corpos enviados em [pedidos].
  Future<({List<LedgerEntry> pendentes, List<LedgerEntry> concluidas})> consultar(
    Map<String, List<Map<String, dynamic>>> porStatus, {
    List<Map<String, dynamic>>? pedidos,
    int? totalConcluidas,
    int? erroNasConcluidas,
    int recusasDasConcluidas = 1 << 30,
  }) {
    var recusas = 0;
    final bybit = MockClient((pedido) async {
      if (pedido.url.path.endsWith('/market/time')) {
        return http.Response(
          jsonEncode({'time': DateTime.now().millisecondsSinceEpoch}),
          200,
        );
      }

      final corpo = jsonDecode(pedido.body) as Map<String, dynamic>;
      pedidos?.add(corpo);
      final status = corpo['statusCode'] as String;
      if (status == '1' &&
          erroNasConcluidas != null &&
          recusas++ < recusasDasConcluidas) {
        return http.Response(
          jsonEncode({'retCode': erroNasConcluidas, 'retMsg': 'limite'}),
          200,
        );
      }

      final data = corpo['page'] == 1
          ? porStatus[status] ?? const []
          : [autorizacao('ctx-pagina-2', '1')];
      final total = status == '1' ? totalConcluidas : null;
      return http.Response(
        jsonEncode({
          'retCode': 0,
          'result': {'data': data, 'totalCount': total ?? data.length},
        }),
        200,
      );
    });

    return http.runWithClient(
      () => BybitClient(
        apiKey: 'chave',
        apiSecret: 'segredo',
        esperaDoLimite: Duration.zero,
      ).cardAuthorizations(),
      () => bybit,
    );
  }

  group('Autorizações do cartão', () {
    test('pede as pendentes e também as concluídas', () async {
      final pedidos = <Map<String, dynamic>>[];
      final r = await consultar(
        {
          '0': [autorizacao('ctx-pendente', '0')],
          '1': [autorizacao('ctx-concluida', '1')],
        },
        pedidos: pedidos,
      );

      expect(pedidos.map((p) => p['statusCode']), ['0', '1']);
      expect(r.pendentes.single.id, 'card-auth-ctx-pendente');
      expect(r.concluidas.single.id, 'card-auth-ctx-concluida');
    });

    test('estornos e reversões ficam de fora das concluídas', () async {
      final r = await consultar({
        '1': [
          autorizacao('ctx-1', '1'),
          autorizacao('ctx-estorno', '1', side: '2'),
          autorizacao('ctx-revertida', '3'),
        ],
      });

      expect(r.concluidas.map((e) => e.id), ['card-auth-ctx-1']);
    });

    test('traz as próximas páginas das concluídas', () async {
      final pedidos = <Map<String, dynamic>>[];
      final r = await consultar(
        {
          '1': [autorizacao('ctx-1', '1')],
        },
        pedidos: pedidos,
        totalConcluidas: 501,
      );

      expect(
        r.concluidas.map((e) => e.id),
        ['card-auth-ctx-1', 'card-auth-ctx-pagina-2'],
      );
      expect(pedidos.where((p) => p['statusCode'] == '1'), hasLength(2));
    });

    test('recusada por excesso de chamadas, tenta de novo', () async {
      final pedidos = <Map<String, dynamic>>[];
      final r = await consultar(
        {
          '1': [autorizacao('ctx-1', '1')],
        },
        pedidos: pedidos,
        erroNasConcluidas: 10006,
        recusasDasConcluidas: 2,
      );

      expect(r.concluidas.single.id, 'card-auth-ctx-1');
      expect(pedidos.where((p) => p['statusCode'] == '1'), hasLength(3));
    });

    test('se as concluídas falharem, as pendentes continuam valendo', () async {
      final r = await consultar(
        {
          '0': [autorizacao('ctx-pendente', '0')],
        },
        erroNasConcluidas: 10006,
      );

      expect(r.pendentes, hasLength(1));
      expect(r.concluidas, isEmpty);
    });
  });
}
