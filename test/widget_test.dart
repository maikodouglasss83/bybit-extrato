import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/budget.dart';
import 'package:bybit_extrato/models.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;

import 'package:bybit_extrato/util/brands.dart';
import 'package:bybit_extrato/util/categorizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Conversão de valores da API', () {
    test('asDouble aceita string, número, nulo e vazio', () {
      expect(asDouble('0.06409769'), closeTo(0.06409769, 1e-12));
      expect(asDouble(12), 12);
      expect(asDouble(null), 0);
      expect(asDouble(''), 0);
    });

    test('depósito entra como valor positivo', () {
      final entry = LedgerEntry.fromDeposit({
        'coin': 'USDT',
        'amount': '150.5',
        'depositFee': '0',
        'status': 3,
        'successAt': '1786317419000',
        'txID': 'abc123',
      });
      expect(entry.change, 150.5);
      expect(entry.isIn, isTrue);
      expect(entry.kind, LedgerKind.deposit);
      expect(entry.status, 'Concluído');
    });

    test('saque entra como valor negativo', () {
      final entry = LedgerEntry.fromWithdraw({
        'coin': 'BTC',
        'amount': '0.25',
        'withdrawFee': '0.0005',
        'status': 'success',
        'createTime': '1786317419000',
        'withdrawId': '99',
      });
      expect(entry.change, -0.25);
      expect(entry.isIn, isFalse);
      expect(entry.kind, LedgerKind.withdraw);
    });

    test('transaction log preserva sinal e saldo posterior', () {
      final entry = LedgerEntry.fromTransactionLog({
        'id': '1',
        'transactionTime': '1786317419000',
        'type': 'TRADE',
        'currency': 'USDT',
        'change': '-30.25',
        'fee': '0.03',
        'cashBalance': '120.5',
        'symbol': 'BTCUSDT',
        'side': 'Buy',
      });
      expect(entry.change, -30.25);
      expect(entry.kind, LedgerKind.trade);
      expect(entry.balanceAfter, 120.5);
      expect(entry.symbol, 'BTCUSDT');
    });
  });

  group('Carteira de fundos', () {
    test('saldo do funding é lido e marcado com a conta certa', () {
      final coin = CoinBalance.fromFunding({
        'coin': 'BRL',
        'walletBalance': '52.26',
        'transferBalance': '52.26',
      });
      expect(coin.coin, 'BRL');
      expect(coin.equity, 52.26);
      expect(coin.account, BybitAccount.funding);
      expect(coin.withUsdValue(9.5).usdValue, 9.5);
    });

    test('transferência interna é neutra e descreve o caminho', () {
      final entry = LedgerEntry.fromInternalTransfer({
        'transferId': 'selfTransfer_abc',
        'coin': 'USDT',
        'amount': '203.8914',
        'fromAccountType': 'UNIFIED',
        'toAccountType': 'FUND',
        'status': 'SUCCESS',
        'timestamp': '1785950606000',
      });
      expect(entry.neutral, isTrue);
      expect(entry.kind, LedgerKind.internalTransfer);
      expect(entry.change, 203.8914);
      expect(entry.note, 'Unificada → Fundos');
      expect(entry.status, 'Concluída');
    });
  });

  group('Bybit Card', () {
    test('compra vira saída com estabelecimento, categoria e pontos', () {
      final entry = LedgerEntry.fromCardTransaction({
        'transactionId': 'cpr-abc',
        'point': 90,
        'side': '1',
        'transactionDate': '1786381342000',
        'transactionAmount': '22.95',
        'basicCurrency': 'BRL',
        'merchName': 'Uber UBER * PENDING',
        'merchCategoryDesc': 'TRANSPORTATION SERVICES',
        'merchCity': 'SAO PAULO',
        'pan4': '1234',
      });
      expect(entry.change, -22.95);
      expect(entry.isCard, isTrue);
      expect(entry.kind, LedgerKind.cardPurchase);
      expect(entry.coin, 'BRL');
      expect(entry.note, 'Uber UBER * PENDING');
      expect(entry.category, 'Transportation Services');
      expect(entry.cardLast4, '1234');
      expect(entry.points, 90);
    });

    test('data zerada cai para a hora em que o registro nasceu', () {
      // A Bybit manda transactionDate "0" enquanto não fecha o lançamento;
      // sem tratar, a compra apareceria datada de 1970.
      final entry = LedgerEntry.fromCardTransaction({
        'transactionId': 'cpr-novo',
        'side': '1',
        'transactionDate': '0',
        'createTime': '1786585210000',
        'transactionAmount': '44.9',
        'basicCurrency': 'BRL',
        'merchName': 'LOJA NOVA',
      });
      expect(entry.time.year, 2026);
    });

    test('estorno entra como valor positivo', () {
      final entry = LedgerEntry.fromCardTransaction({
        'transactionId': 'cpr-xyz',
        'side': '2',
        'transactionDate': '1786381342000',
        'transactionAmount': '10.00',
        'basicCurrency': 'BRL',
      });
      expect(entry.change, 10);
      expect(entry.kind, LedgerKind.cardRefund);
      expect(entry.isIn, isTrue);
    });

    test('pontos e teto de cashback são lidos', () {
      final r = CardRewards.fromBalance({'availablePoint': '6253', 'pendingPoint': '2769'})
          .copyWithTier({'usedLimit': '17.54', 'limit': '50.00', 'unit': 'USD'});
      expect(r.availablePoints, 6253);
      expect(r.pendingPoints, 2769);
      expect(r.limitProgress, closeTo(0.3508, 0.001));
      expect(r.hasData, isTrue);
    });
  });

  group('Categorização automática', () {
    // Estabelecimentos como a Bybit realmente devolve, com abreviações e
    // prefixos de adquirente.
    const casos = {
      'Uber UBER * PENDING': SpendCategories.transporte,
      'UBER *ONE MEMBERSHIP U': SpendCategories.assinaturas,
      'BILHUNICO': SpendCategories.transporte,
      'NETFLIX.COM': SpendCategories.assinaturas,
      'DM*Spotify': SpendCategories.assinaturas,
      'AmazonPrimeBR': SpendCategories.assinaturas,
      'DM *gotindercomhelp': SpendCategories.assinaturas,
      'CLARO37': SpendCategories.telefonia,
      'NET PGT*Fatura Claro': SpendCategories.telefonia,
      'TIM*TIM': SpendCategories.telefonia,
      'MERCADOLIVRE*MERCADOLI': SpendCategories.compras,
      'MP          *MELIMAIS': SpendCategories.compras,
      'MERCADINHO DO TICO': SpendCategories.mercado,
      'MERCADO FLAMENGO': SpendCategories.mercado,
      'ANTHROPIC* CLAUDE SUB': SpendCategories.tecnologia,
      'DL*GOOGLE Google': SpendCategories.tecnologia,
      'HTM*L Inteligncia Arti': SpendCategories.tecnologia,
    };

    casos.forEach((estabelecimento, esperado) {
      test('"$estabelecimento" vira $esperado', () {
        expect(categorizeMerchant(estabelecimento), esperado);
      });
    });

    test('e-commerce não é confundido com supermercado', () {
      expect(categorizeMerchant('MERCADOLIVRE*MERCADOLI'), SpendCategories.compras);
      expect(categorizeMerchant('MERCADINHO DO TICO'), SpendCategories.mercado);
    });

    test('assinatura da Amazon não vira compra na Amazon', () {
      expect(categorizeMerchant('AmazonPrimeBR'), SpendCategories.assinaturas);
      expect(categorizeMerchant('Amazon.com.br'), SpendCategories.compras);
    });

    test('nome de pessoa é tratado como transferência', () {
      expect(
        categorizeMerchant('MAIKO DOUGLAS SANTOS SILV'),
        SpendCategories.transferencias,
      );
    });

    test('sem nome e sem correspondência cai em Outros', () {
      expect(categorizeMerchant(''), SpendCategories.outros);
      expect(categorizeMerchant(null), SpendCategories.outros);
      expect(categorizeMerchant('XYZ123 QWE'), SpendCategories.outros);
    });

    test('categoria vinda da API tem prioridade', () {
      expect(
        categorizeMerchant('NETFLIX.COM', apiCategory: 'Entretenimento'),
        'Entretenimento',
      );
    });

    test('acentos e caixa não atrapalham', () {
      expect(categorizeMerchant('farmácia SÃO PAULO'), SpendCategories.saude);
      expect(categorizeMerchant('PADARIA do Zé'), SpendCategories.mercado);
    });
  });

  group('Histórico guardado no dispositivo', () {
    test('lançamento sobrevive à ida e volta em JSON', () {
      final original = LedgerEntry.fromCardTransaction({
        'transactionId': 'cpr-123',
        'side': '1',
        'transactionDate': '1786554303000',
        'transactionAmount': '44.9',
        'basicCurrency': 'BRL',
        'merchName': 'HTM*FOGUEIRA',
        'merchCity': 'Novo Hamburgo BRA',
        'pan4': '4469',
        'point': 87,
      });

      final volta = LedgerEntry.fromCache(original.toJson());

      expect(volta.id, original.id);
      expect(volta.time, original.time);
      expect(volta.kind, original.kind);
      expect(volta.coin, original.coin);
      expect(volta.change, original.change);
      expect(volta.note, original.note);
      expect(volta.category, original.category);
      expect(volta.cardLast4, original.cardLast4);
      expect(volta.points, original.points);
      expect(volta.isCard, isTrue);
    });

    test('transferência neutra não perde a marcação ao ser guardada', () {
      final original = LedgerEntry.fromInternalTransfer({
        'transferId': 'abc',
        'coin': 'USDT',
        'amount': '203.89',
        'fromAccountType': 'UNIFIED',
        'toAccountType': 'FUND',
        'status': 'SUCCESS',
        'timestamp': '1785950606000',
      });

      final volta = LedgerEntry.fromCache(original.toJson());
      expect(volta.neutral, isTrue);
      expect(volta.note, 'Unificada → Fundos');
      expect(volta.kind, LedgerKind.internalTransfer);
    });
  });

  group('Evolução dos gastos', () {
    LedgerEntry compraEm(String id, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': id,
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': 'LOJA',
        });

    test('agrupa por mês, do mais antigo para o mais recente', () {
      final state = AppState()
        ..seedEntries([
          compraEm('a', 100, DateTime(2026, 3, 5)),
          compraEm('b', 50, DateTime(2026, 3, 20)),
          compraEm('c', 300, DateTime(2026, 5, 2)),
        ]);

      final meses = state.monthlySpending();
      expect(meses.length, 2);
      expect(meses.first.key.month, 3);
      expect(meses.first.value, 150);
      expect(meses.last.key.month, 5);
      expect(meses.last.value, 300);
    });

    test('respeita o limite de meses, mantendo os mais recentes', () {
      final state = AppState()
        ..seedEntries([
          for (var m = 1; m <= 8; m++) compraEm('m$m', m * 10, DateTime(2026, m, 10)),
        ]);

      final meses = state.monthlySpending(months: 3);
      expect(meses.length, 3);
      expect(meses.map((e) => e.key.month), [6, 7, 8]);
    });

    test('gasto oculto não entra na evolução', () async {
      final state = AppState()
        ..seedEntries([
          compraEm('a', 100, DateTime(2026, 4, 5)),
          compraEm('b', 400, DateTime(2026, 4, 6)),
        ]);

      final oculta = state.cardEntries.firstWhere((e) => e.id.endsWith('b'));
      await state.setHidden(oculta, true);

      expect(state.monthlySpending().single.value, 100);
    });

    test('"Tudo" (zero meses) traz o histórico inteiro', () {
      final state = AppState()
        ..seedEntries([
          for (var m = 1; m <= 8; m++) compraEm('m$m', m * 10, DateTime(2026, m, 10)),
        ]);

      expect(state.monthlySpending(months: 0).length, 8);
      expect(state.monthlySpending(months: 1).length, 1);
      expect(state.monthlySpending(months: 12).length, 8);
    });

    test('o período escolhido vale para o gráfico', () {
      final state = AppState()
        ..seedEntries([
          for (var m = 1; m <= 8; m++) compraEm('m$m', m * 10, DateTime(2026, m, 10)),
        ]);

      expect(state.monthlyRange, 6);
      expect(state.monthlyRangeLabel, '6 meses');

      state.setMonthlyRange(3);
      expect(state.monthlySpending(months: state.monthlyRange).length, 3);
      expect(state.monthlyRangeLabel, '3 meses');

      state.setMonthlyRange(0);
      expect(state.monthlySpending(months: state.monthlyRange).length, 8);
      expect(state.monthlyRangeLabel, 'Tudo');
    });

    test('sem compras, não devolve nada', () {
      expect(AppState().monthlySpending(), isEmpty);
    });
  });

  group('Planejamento financeiro', () {
    LedgerEntry compra(String id, String merch, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': id,
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': merch,
        });

    final junho = DateTime(2026, 6, 15);
    late AppState state;

    setUp(() {
      state = AppState()
        ..seedEntries([
          compra('m1', 'MERCADINHO DO TICO', 300, junho), // Mercado
          compra('r1', 'IFOOD', 200, junho), // Restaurantes
          compra('u1', 'UBER', 150, junho), // Transporte
          compra('n1', 'NETFLIX.COM', 50, junho), // Assinaturas
        ])
        ..selectMonth(junho);
    });

    test('a estrutura padrão traz as categorias principais pedidas', () {
      final nomes = state.mainBudgetNodes.map((n) => n.name).toList();
      expect(
        nomes,
        containsAll([
          'Casa',
          'Educação',
          'Lazer',
          'Saúde',
          'Alimentação',
          'Transporte',
          'Despesas pessoais',
          'Comunicação',
          'Tarifas e impostos',
          'Outros',
          'Sem categoria',
        ]),
      );
    });

    test('o gasto cai na categoria certa e soma nas subcategorias', () {
      final linhas = state.budgetLines(junho);
      final alimentacao = linhas.firstWhere((l) => l.node.id == 'alimentacao');

      // Mercado (300) + Restaurantes (200)
      expect(alimentacao.spent, 500);
      expect(alimentacao.children.map((c) => c.node.name),
          containsAll(['Mercado', 'Restaurantes e delivery']));
      expect(
        alimentacao.children.firstWhere((c) => c.node.name == 'Mercado').spent,
        300,
      );

      final transporte = linhas.firstWhere((l) => l.node.id == 'transporte');
      expect(transporte.spent, 150);
    });

    test('"Sem categoria" fica sempre por último na lista', () async {
      // Mesmo recebendo o maior gasto de todos, ela não sobe.
      await state.setBudgetSources('alimentacao_mercado', const []);
      await state.setBudgetSources('alimentacao_restaurantes', const []);

      final linhas = state.budgetLines(junho);
      expect(linhas.last.node.id, kUncategorizedId);
      expect(linhas.last.spent, 500);
    });

    test('o total do topo bate com a soma das categorias', () {
      expect(state.budgetSpentTotal(junho), 700);
    });

    test('meta da principal manda; sem ela vale a soma das filhas', () async {
      // Sem meta em lugar nenhum.
      expect(state.budgetTotal(junho), 0);

      // Meta só nas subcategorias soma para o grupo.
      await state.setBudget('alimentacao_mercado', 400);
      await state.setBudget('alimentacao_restaurantes', 100);
      var alimentacao =
          state.budgetLines(junho).firstWhere((l) => l.node.id == 'alimentacao');
      expect(alimentacao.budget, 500);

      // Definida na principal, ela passa a valer para o grupo.
      await state.setBudget('alimentacao', 800);
      alimentacao =
          state.budgetLines(junho).firstWhere((l) => l.node.id == 'alimentacao');
      expect(alimentacao.budget, 800);
    });

    test('quanto resta e quando estoura', () async {
      await state.setBudget('alimentacao', 800);
      final alimentacao =
          state.budgetLines(junho).firstWhere((l) => l.node.id == 'alimentacao');
      expect(alimentacao.remaining, 300);
      expect(alimentacao.exceeded, isFalse);
      expect(alimentacao.progress, closeTo(0.625, 1e-9));

      await state.setBudget('transporte', 100);
      final transporte =
          state.budgetLines(junho).firstWhere((l) => l.node.id == 'transporte');
      expect(transporte.exceeded, isTrue);
      expect(transporte.remaining, -50);
      expect(transporte.progress, 1.0);
    });

    test('criar categoria com origem tira o gasto de onde estava', () async {
      await state.addBudgetNode(
        name: 'Delivery',
        parentId: 'casa',
        sources: [SpendCategories.restaurantes],
      );

      final linhas = state.budgetLines(junho);
      // Restaurantes saiu de Alimentação…
      expect(linhas.firstWhere((l) => l.node.id == 'alimentacao').spent, 300);
      // …e entrou em Casa, sem o total mudar.
      expect(linhas.firstWhere((l) => l.node.id == 'casa').spent, 200);
      expect(state.budgetSpentTotal(junho), 700);
    });

    test('gasto sem categoria mapeada cai em "Sem categoria"', () async {
      // Tira Assinaturas de Lazer sem colocar em lugar nenhum.
      await state.setBudgetSources('lazer_assinaturas', const []);

      final linhas = state.budgetLines(junho);
      expect(linhas.firstWhere((l) => l.node.id == kUncategorizedId).spent, 50);
      expect(state.budgetSpentTotal(junho), 700);
    });

    test('categoria padrão não pode ser apagada; a criada sim', () async {
      await state.removeBudgetNode('alimentacao');
      expect(state.mainBudgetNodes.any((n) => n.id == 'alimentacao'), isTrue);

      await state.addBudgetNode(name: 'Pets');
      final pets = state.mainBudgetNodes.firstWhere((n) => n.name == 'Pets');
      await state.addBudgetNode(name: 'Ração', parentId: pets.id);
      expect(state.childrenOf(pets.id).length, 1);

      await state.removeBudgetNode(pets.id);
      expect(state.mainBudgetNodes.any((n) => n.name == 'Pets'), isFalse);
      // A subcategoria vai junto.
      expect(state.budgetNodes.any((n) => n.name == 'Ração'), isFalse);
    });

    test('a meta é digitada na moeda da tela e guardada em reais', () async {
      state.usdBrl = 5.0;

      // Em real, o que se digita é o que se guarda.
      state.preferBrl = true;
      await state.setBudget('transporte', state.displayToBrl(500));
      expect(
        state.budgetNodes.firstWhere((n) => n.id == 'transporte').budget,
        500,
      );

      // Em dólar, US$ 100 viram R$ 500 no armazenamento…
      state.preferBrl = false;
      await state.setBudget('transporte', state.displayToBrl(100));
      expect(
        state.budgetNodes.firstWhere((n) => n.id == 'transporte').budget,
        500,
      );
      // …e voltam como US$ 100 na hora de editar.
      expect(state.brlToDisplay(500), 100);
    });

    test('gasto oculto fica de fora do planejamento', () async {
      final uber = state.cardEntries.firstWhere((e) => e.id.endsWith('u1'));
      await state.setHidden(uber, true);
      expect(state.budgetSpentTotal(junho), 550);
      expect(
        state.budgetLines(junho).firstWhere((l) => l.node.id == 'transporte').spent,
        0,
      );
    });
  });

  group('Meta do nível do cartão e conversão de moeda', () {
    LedgerEntry compraBrl(String id, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': id,
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': 'LOJA $id',
        });

    late AppState state;
    final agora = DateTime.now();

    setUp(() {
      // Dólar a 5,00 deixa a conta redonda: R$ 1.000 = US$ 200.
      state = AppState()
        ..usdBrl = 5.0
        ..seedEntries([
          compraBrl('a', 600, agora),
          compraBrl('b', 400, agora),
        ]);
    });

    test(r'a meta padrão é de US$ 500', () {
      expect(state.cardGoalUsd, 500);
    });

    test('gasto em real conta para a meta já convertido em dólar', () {
      expect(state.cardSpentUsdThisMonth, 200);
      expect(state.cardGoalRemainingUsd, 300);
      expect(state.cardGoalProgress, closeTo(0.4, 1e-9));
      expect(state.cardGoalReached, isFalse);
    });

    test('bater a meta zera o que falta', () async {
      state.seedEntries([compraBrl('c', 3000, agora)]);
      expect(state.cardSpentUsdThisMonth, 600);
      expect(state.cardGoalReached, isTrue);
      expect(state.cardGoalRemainingUsd, 0);
      expect(state.cardGoalProgress, 1.0);
    });

    test('gasto oculto não conta para a meta', () async {
      final oculta = state.cardEntries.firstWhere((e) => e.id.endsWith('a'));
      await state.setHidden(oculta, true);
      expect(state.cardSpentUsdThisMonth, 80);
    });

    test('mudar a moeda converte os valores em real', () {
      // Em real, mostra como veio da fatura.
      state.preferBrl = true;
      expect(state.formatValue(-100, 'BRL', signed: false), contains('100,00'));
      expect(state.formatValue(-100, 'BRL', signed: false), startsWith(r'R$'));

      // Em dólar, o mesmo gasto vira US$ 20,00.
      state.preferBrl = false;
      expect(state.formatValue(-100, 'BRL', signed: false), startsWith(r'US$'));
      expect(state.formatValue(-100, 'BRL', signed: false), contains('20,00'));
    });

    test('cripto de verdade mantém a quantidade', () {
      state.prices = {'BTC': 100000};
      state.preferBrl = false;
      // Não vira dinheiro: 0,5 BTC continua 0,5 BTC.
      expect(state.formatValue(0.5, 'BTC', signed: false), contains('0,5'));
      expect(state.showsConverted('BTC'), isFalse);
      expect(state.showsConverted('BRL'), isTrue);
    });

    test('sem cotação, o valor em real não é convertido para dólar', () {
      final semCotacao = AppState()..preferBrl = false;
      expect(semCotacao.formatValue(-100, 'BRL', signed: false), contains('100'));
    });
  });

  group('Identidade das marcas', () {
    test('reconhece as marcas mesmo com o lixo do adquirente no nome', () {
      expect(brandFor('NETFLIX.COM')?.label, 'N');
      expect(brandFor('DM*Spotify')?.label, 'S');
      expect(brandFor('MERCADOLIVRE*MERCADOLI')?.label, 'ML');
      expect(brandFor('MP          *MELIMAIS')?.label, 'ML');
      expect(brandFor('Uber UBER * PENDING')?.label, 'U');
      expect(brandFor('CLARO37')?.label, 'C');
      expect(brandFor('ANTHROPIC* CLAUDE SUB')?.label, 'C');
      expect(brandFor('AmazonPrimeBR')?.label, 'P');
      expect(brandFor('HOTMART Pinho-FOGUEIRA')?.label, 'H');
    });

    test('cada marca tem a cor e o domínio certos', () {
      final netflix = brandFor('NETFLIX.COM')!;
      expect(netflix.color, const Color(0xFFE50914));
      expect(netflix.domain, 'netflix.com');

      final spotify = brandFor('DM*Spotify')!;
      expect(spotify.color, const Color(0xFF1DB954));
    });

    test('estabelecimento sem marca conhecida devolve nulo', () {
      expect(brandFor('MERCADINHO DO TICO'), isNull);
      expect(brandFor('VILA DECK'), isNull);
      expect(brandFor(''), isNull);
      expect(brandFor(null), isNull);
    });

    test('logos da internet ficam desligados por padrão', () {
      expect(AppState().useOnlineLogos, isFalse);
    });
  });

  group('Ajustes manuais de nome e categoria', () {
    LedgerEntry compraEm(String estabelecimento, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': '$estabelecimento-$valor-${quando.millisecondsSinceEpoch}',
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': estabelecimento,
        });

    final abril = DateTime(2026, 4, 12);
    late AppState state;
    late LedgerEntry meli;
    late LedgerEntry meliOutraCompra;

    setUp(() {
      meli = compraEm('MERCADOLIVRE*MERCADOLI', 100, abril);
      meliOutraCompra = compraEm('MERCADOLIVRE*MERCADOLI', 30, abril);
      state = AppState()
        ..seedEntries([meli, meliOutraCompra, compraEm('NETFLIX.COM', 20, abril)])
        ..selectMonth(abril);
    });

    test('sem ajuste, mostra o nome e a categoria automáticos', () {
      expect(state.displayNameOf(meli), 'MERCADOLIVRE*MERCADOLI');
      expect(state.categoryOf(meli), SpendCategories.compras);
      expect(state.hasCustomizations(meli), isFalse);
    });

    test('renomear e recategorizar vale para o mesmo estabelecimento', () async {
      await state.setEntryOverrides(meli,
          name: 'Mercado Livre', category: SpendCategories.casa);

      expect(state.displayNameOf(meli), 'Mercado Livre');
      expect(state.categoryOf(meli), SpendCategories.casa);
      // A outra compra no mesmo lugar acompanha.
      expect(state.displayNameOf(meliOutraCompra), 'Mercado Livre');
      expect(state.categoryOf(meliOutraCompra), SpendCategories.casa);
      // O nome original continua disponível para conferência.
      expect(state.originalNameOf(meli), 'MERCADOLIVRE*MERCADOLI');
    });

    test('ajuste não vaza para outro estabelecimento', () async {
      await state.setEntryOverrides(meli, name: 'Mercado Livre');
      final netflix = state.cardEntries.firstWhere((e) => e.note == 'NETFLIX.COM');
      expect(state.displayNameOf(netflix), 'NETFLIX.COM');
      expect(state.hasCustomizations(netflix), isFalse);
    });

    test('nome vazio ou igual ao original não conta como personalização', () async {
      await state.setEntryOverrides(meli, name: '   ');
      expect(state.hasCustomName(meli), isFalse);
      await state.setEntryOverrides(meli, name: 'MERCADOLIVRE*MERCADOLI');
      expect(state.hasCustomName(meli), isFalse);
      expect(state.displayNameOf(meli), 'MERCADOLIVRE*MERCADOLI');
    });

    test('passar só a categoria preserva o nome ajustado', () async {
      await state.setEntryOverrides(meli, name: 'Mercado Livre');
      await state.setEntryOverrides(meli, category: SpendCategories.lazer);
      expect(state.displayNameOf(meli), 'Mercado Livre');
      expect(state.categoryOf(meli), SpendCategories.lazer);
    });

    test('a categoria ajustada muda o total por categoria', () async {
      expect(
        state.categoryBreakdown(abril).firstWhere((c) => c.label == SpendCategories.compras).total,
        130,
      );
      await state.setEntryOverrides(meli, category: SpendCategories.mercado);
      final categorias = state.categoryBreakdown(abril);
      expect(categorias.any((c) => c.label == SpendCategories.compras), isFalse);
      expect(
        categorias.firstWhere((c) => c.label == SpendCategories.mercado).total,
        130,
      );
    });

    test('restaurar devolve nome e categoria automáticos', () async {
      await state.setEntryOverrides(meli,
          name: 'Mercado Livre', category: SpendCategories.casa);
      expect(state.customizedMerchantCount, 1);

      await state.clearOverridesFor(meli);
      expect(state.displayNameOf(meli), 'MERCADOLIVRE*MERCADOLI');
      expect(state.categoryOf(meli), SpendCategories.compras);
      expect(state.customizedMerchantCount, 0);
    });
  });

  group('Gastos por categoria', () {
    LedgerEntry compra(String categoria, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': '$categoria-$valor-${quando.millisecondsSinceEpoch}',
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchCategoryDesc': categoria,
        });

    final marco = DateTime(2026, 3, 10);
    final fevereiro = DateTime(2026, 2, 10);

    late AppState state;

    setUp(() {
      state = AppState()
        ..seedEntries([
          compra('MERCADO', 100, marco),
          compra('MERCADO', 50, marco),
          compra('TRANSPORTE', 50, marco),
          compra('MERCADO', 400, fevereiro),
        ])
        ..selectMonth(marco);
    });

    test('agrupa e ordena as categorias do mês selecionado', () {
      final categorias = state.categoryBreakdown(marco);
      expect(categorias.length, 2);
      expect(categorias.first.label, 'Mercado');
      expect(categorias.first.total, 150);
      expect(categorias.first.count, 2);
      expect(categorias.first.share, closeTo(0.75, 1e-9));
      expect(categorias.last.label, 'Transporte');
      expect(categorias.last.share, closeTo(0.25, 1e-9));
    });

    test('total do mês ignora compras de outros meses', () {
      expect(state.cardSpentInMonth(marco), 200);
      expect(state.cardSpentInMonth(fevereiro), 400);
    });

    test('meses com dados vêm do mais recente para o mais antigo', () {
      final meses = state.monthsWithCardData;
      expect(meses.length, 2);
      expect(meses.first.month, 3);
      expect(meses.last.month, 2);
    });

    test('não avança para além do mês atual', () {
      final agora = DateTime.now();
      state.selectMonth(DateTime(agora.year, agora.month));
      expect(state.canGoToNextMonth, isFalse);
      state.shiftMonth(1);
      expect(state.selectedMonth.month, agora.month);
      state.shiftMonth(-1);
      expect(state.canGoToNextMonth, isTrue);
    });
  });

  group('Gasto fixo e variável', () {
    LedgerEntry compra(String id, String merch, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': id,
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': merch,
        });

    final setembro = DateTime(2026, 9, 10);
    late AppState state;
    late LedgerEntry netflix;
    late LedgerEntry mercado;
    late LedgerEntry claro;

    setUp(() {
      netflix = compra('n', 'NETFLIX.COM', 50, setembro); // Assinaturas
      claro = compra('c', 'CLARO37', 100, setembro); // Telefonia
      mercado = compra('m', 'MERCADINHO DO TICO', 200, setembro); // Mercado
      state = AppState()
        ..seedEntries([netflix, claro, mercado])
        ..selectMonth(setembro);
    });

    test('assinatura e telefone nascem como fixos; mercado, variável', () {
      expect(state.isFixed(netflix), isTrue);
      expect(state.isFixed(claro), isTrue);
      expect(state.isFixed(mercado), isFalse);
      // Nada disso foi decidido à mão ainda.
      expect(state.hasFixedOverride(netflix), isFalse);
    });

    test('soma separa compromisso de gasto do dia a dia', () {
      final d = state.fixedVsVariable(setembro);
      expect(d.fixo, 150);
      expect(d.variavel, 200);
    });

    test('a escolha do usuário vence o palpite', () async {
      await state.setFixed(netflix, false);
      expect(state.isFixed(netflix), isFalse);
      expect(state.hasFixedOverride(netflix), isTrue);
      expect(state.fixedVsVariable(setembro).fixo, 100);

      await state.setFixed(mercado, true);
      expect(state.fixedVsVariable(setembro).fixo, 300);
      expect(state.fixedVsVariable(setembro).variavel, 50);
    });

    test('desfazer devolve ao palpite da categoria', () async {
      await state.setFixed(netflix, false);
      await state.clearFixedOverride(netflix);
      expect(state.isFixed(netflix), isTrue);
      expect(state.hasFixedOverride(netflix), isFalse);
    });

    test('mudar a categoria muda o palpite junto', () async {
      // Mercado vira assinatura: passa a contar como compromisso.
      await state.setEntryOverrides(mercado, category: SpendCategories.assinaturas);
      expect(state.isFixed(mercado), isTrue);
      expect(state.fixedVsVariable(setembro).fixo, 350);
    });

    test('gasto oculto não entra em nenhum dos dois lados', () async {
      await state.setHidden(claro, true);
      final d = state.fixedVsVariable(setembro);
      expect(d.fixo, 50);
      expect(d.variavel, 200);
    });

    test('fração mínima de fixo não zera o peso da barra', () {
      // Um fixo insignificante perto do total: o peso da barra arredondava
      // para zero e derrubava a tela.
      final state = AppState()
        ..seedEntries([
          compra('n', 'NETFLIX.COM', 0.01, setembro), // fixo
          compra('m', 'MERCADINHO DO TICO', 100000, setembro), // variável
        ]);

      final d = state.fixedVsVariable(setembro);
      final total = d.fixo + d.variavel;
      final fracao = d.fixo / total;

      expect(fracao, greaterThan(0));
      // É este arredondamento que precisa de piso 1 na interface.
      expect((fracao * 1000).round(), 0);
      expect(math.max(1, (fracao * 1000).round()), 1);
    });

    test('lista de compromissos usa o apelido e vem ordenada', () async {
      await state.setEntryOverrides(claro, name: 'Claro');
      final fixos = state.fixedMerchants(setembro);
      expect(fixos.first.key, 'Claro');
      expect(fixos.first.value, 100);
      expect(fixos.map((e) => e.key), contains('NETFLIX.COM'));
    });
  });

  group('Mesma marca, grafias diferentes', () {
    LedgerEntry compra(String id, String merch, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': id,
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': merch,
        });

    test('as variações da Bybit viram um estabelecimento só', () {
      // Exatamente o que aparecia duplicado na agenda.
      expect(
        AppState.merchantKeyFor('DM*Spotify'),
        AppState.merchantKeyFor('DM *Spotify'),
      );
      expect(
        AppState.merchantKeyFor('NETFLIX.COM'),
        AppState.merchantKeyFor('NETFLIX ENTRETENIMENTO'),
      );
      expect(
        AppState.merchantKeyFor('MERCADOLIVRE*MERCADOLI'),
        AppState.merchantKeyFor('MP          *MELIMAIS'),
      );
    });

    test('estabelecimentos diferentes continuam separados', () {
      expect(
        AppState.merchantKeyFor('NETFLIX.COM'),
        isNot(AppState.merchantKeyFor('DM*Spotify')),
      );
      expect(
        AppState.merchantKeyFor('MERCADINHO DO TICO'),
        isNot(AppState.merchantKeyFor('MERCADO FLAMENGO')),
      );
    });

    test('sem marca conhecida, só os espaços são normalizados', () {
      expect(
        AppState.merchantKeyFor('MERCADINHO   DO    TICO'),
        AppState.merchantKeyFor('mercadinho do tico'),
      );
    });

    test('o compromisso não se duplica entre as grafias', () async {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'DM*Spotify', 31.90, DateTime(mes.year, mes.month - 1, 4)),
          compra('b', 'DM *Spotify', 31.90, DateTime(mes.year, mes.month, 4)),
        ]);

      final previsoes = state.fixedForecast(mes);
      expect(previsoes.length, 1);
      // E o que já caiu neste mês aparece como pago, não como atrasado.
      expect(previsoes.single.paid, isTrue);
      expect(state.pendingFixedInMonth(mes), 0);
    });

    test('renomear uma grafia vale para todas', () async {
      final agora = DateTime.now();
      final state = AppState()
        ..seedEntries([
          compra('a', 'DM*Spotify', 31.90, DateTime(agora.year, agora.month, 4)),
          compra('b', 'DM *Spotify', 31.90, DateTime(agora.year, agora.month, 4)),
        ]);

      final primeira = state.cardEntries.first;
      await state.setEntryOverrides(primeira, name: 'Spotify');

      for (final e in state.cardEntries) {
        expect(state.displayNameOf(e), 'Spotify');
      }
    });
  });

  group('Previsão dos compromissos', () {
    LedgerEntry compra(String id, String merch, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': id,
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': merch,
        });

    test('deduz o dia costumeiro e o valor da última vez', () {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20.90, DateTime(mes.year, mes.month - 3, 9)),
          compra('b', 'NETFLIX.COM', 20.90, DateTime(mes.year, mes.month - 2, 9)),
          compra('c', 'NETFLIX.COM', 24.90, DateTime(mes.year, mes.month - 1, 10)),
        ]);

      final previsao = state.fixedForecast(mes).single;
      expect(previsao.merchant, 'NETFLIX.COM');
      expect(previsao.expectedDay, 9); // mediana de 9, 9, 10
      expect(previsao.expectedAmount, 24.90); // o mais recente
      expect(previsao.paid, isFalse);
      expect(previsao.monthsSeen, 3);
    });

    test('um mês só de histórico não vira previsão', () {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20.90, DateTime(mes.year, mes.month - 1, 9)),
        ]);
      expect(state.fixedForecast(mes), isEmpty);
    });

    test('marca como pago quando já caiu no mês', () {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20.90, DateTime(mes.year, mes.month - 1, 5)),
          compra('b', 'NETFLIX.COM', 21.90, DateTime(mes.year, mes.month, 5)),
        ]);

      final previsao = state.fixedForecast(mes).single;
      expect(previsao.paid, isTrue);
      expect(previsao.paidDate!.day, 5);
      expect(previsao.expectedAmount, 21.90); // o que de fato foi cobrado
      expect(state.pendingFixedInMonth(mes), 0);
    });

    test('o que falta pagar soma só os pendentes', () {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          // Já pago neste mês.
          compra('a', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month - 1, 5)),
          compra('b', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month, 5)),
          // Ainda não caiu.
          compra('c', 'CLARO37', 100, DateTime(mes.year, mes.month - 2, 20)),
          compra('d', 'CLARO37', 100, DateTime(mes.year, mes.month - 1, 20)),
        ]);

      expect(state.pendingFixedInMonth(mes), 100);
      // O pendente vem antes do pago na lista.
      expect(state.fixedForecast(mes).first.merchant, 'CLARO37');
      expect(state.fixedForecast(mes).first.paid, isFalse);
    });

    test('dia 31 não escapa para o mês seguinte em fevereiro', () {
      final fevereiro = DateTime(2027, 2);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20, DateTime(2026, 12, 31)),
          compra('b', 'NETFLIX.COM', 20, DateTime(2027, 1, 31)),
        ]);

      final previsao = state.fixedForecast(fevereiro).single;
      expect(previsao.expectedDay, 28);
      expect(previsao.expectedDate.month, 2);
    });

    test('o dia definido à mão manda no palpite do histórico', () async {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month - 2, 9)),
          compra('b', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month - 1, 9)),
        ]);

      expect(state.fixedForecast(mes).single.expectedDay, 9);
      expect(state.fixedForecast(mes).single.confirmedDay, isFalse);

      final netflix = state.cardEntries.first;
      await state.setDueDay(netflix, 20);

      final previsao = state.fixedForecast(mes).single;
      expect(previsao.expectedDay, 20);
      expect(previsao.confirmedDay, isTrue);
      expect(state.dueDayOf(netflix), 20);
    });

    test('com dia definido, um mês só de histórico já vira previsão', () async {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month - 1, 9)),
        ]);

      // Sem o dia, um mês só não basta.
      expect(state.fixedForecast(mes), isEmpty);

      await state.setDueDay(state.cardEntries.first, 15);
      expect(state.fixedForecast(mes).single.expectedDay, 15);
    });

    test('dia definido também respeita meses curtos', () async {
      final fevereiro = DateTime(2027, 2);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20, DateTime(2027, 1, 10)),
          compra('b', 'NETFLIX.COM', 20, DateTime(2026, 12, 10)),
        ]);

      await state.setDueDay(state.cardEntries.first, 31);
      expect(state.fixedForecast(fevereiro).single.expectedDay, 28);
    });

    test('remover o dia devolve ao palpite do histórico', () async {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month - 2, 9)),
          compra('b', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month - 1, 9)),
        ]);

      final netflix = state.cardEntries.first;
      await state.setDueDay(netflix, 20);
      await state.setDueDay(netflix, null);

      expect(state.dueDayOf(netflix), isNull);
      expect(state.fixedForecast(mes).single.expectedDay, 9);
      expect(state.fixedForecast(mes).single.confirmedDay, isFalse);
    });

    test('dia fora do intervalo é recusado', () async {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'NETFLIX.COM', 20, DateTime(mes.year, mes.month - 1, 9)),
        ]);

      final netflix = state.cardEntries.first;
      await state.setDueDay(netflix, 0);
      expect(state.dueDayOf(netflix), isNull);
      await state.setDueDay(netflix, 32);
      expect(state.dueDayOf(netflix), isNull);
    });

    test('a previsão leva à lista de cobranças do estabelecimento', () {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          // Mesma marca, grafias diferentes: tudo cai no mesmo compromisso.
          compra('a', 'DM*Spotify', 31.90, DateTime(mes.year, mes.month - 2, 4)),
          compra('b', 'DM *Spotify', 31.90, DateTime(mes.year, mes.month - 1, 4)),
          compra('c', 'MERCADINHO DO TICO', 10, DateTime(mes.year, mes.month, 1)),
        ]);

      final previsao = state.fixedForecast(mes).single;
      final cobrancas = state.entriesOfMerchant(previsao.merchantKey);

      expect(cobrancas.length, 2);
      // Da mais recente para a mais antiga.
      expect(cobrancas.first.time.isAfter(cobrancas.last.time), isTrue);
      // E sem misturar com outro estabelecimento.
      expect(cobrancas.any((e) => e.note == 'MERCADINHO DO TICO'), isFalse);
    });

    test('gasto variável não entra na previsão', () {
      final agora = DateTime.now();
      final mes = DateTime(agora.year, agora.month);
      final state = AppState()
        ..seedEntries([
          compra('a', 'MERCADINHO DO TICO', 50, DateTime(mes.year, mes.month - 1, 8)),
          compra('b', 'MERCADINHO DO TICO', 60, DateTime(mes.year, mes.month - 2, 8)),
        ]);
      expect(state.fixedForecast(mes), isEmpty);
    });
  });

  group('Moeda padrão', () {
    test('o real é o padrão quando há cotação', () {
      final state = AppState()..usdBrl = 5.0;
      expect(state.showInBrl, isTrue);
      expect(state.waitingForRate, isFalse);
      expect(state.displayCurrencySymbol, r'R$ ');
    });

    test('sem cotação cai para dólar em vez de mentir o símbolo', () {
      // O risco: mostrar o número em dólar com "R$" na frente.
      final state = AppState();
      expect(state.usdBrl, isNull);
      expect(state.showInBrl, isFalse);
      expect(state.waitingForRate, isTrue);
      expect(state.displayCurrencySymbol, r'US$ ');

      // Um valor em dólar não pode virar real sem cotação.
      expect(state.toDisplay(10), 10);
    });

    test('quando a cotação chega, o real passa a valer sozinho', () {
      final state = AppState();
      expect(state.showInBrl, isFalse);

      state.usdBrl = 5.0;
      expect(state.showInBrl, isTrue);
      expect(state.toDisplay(10), 50);
    });
  });

  group('Ocultar um gasto', () {
    LedgerEntry compraEm(String id, String merch, double valor, DateTime quando) =>
        LedgerEntry.fromCardTransaction({
          'transactionId': id,
          'side': '1',
          'transactionDate': '${quando.millisecondsSinceEpoch}',
          'transactionAmount': '$valor',
          'basicCurrency': 'BRL',
          'merchName': merch,
        });

    final maio = DateTime(2026, 5, 20);
    late AppState state;
    late LedgerEntry transferencia;
    late LedgerEntry mercado;

    setUp(() {
      transferencia = compraEm('t1', 'FULANO DE TAL SILVA', 990, maio);
      mercado = compraEm('m1', 'MERCADINHO DO TICO', 10, maio);
      state = AppState()
        ..seedEntries([transferencia, mercado])
        ..selectMonth(maio);
    });

    test('ocultar tira o gasto do total, mas ele continua na lista', () async {
      expect(state.cardSpentInMonth(maio), 1000);
      expect(state.cardEntriesForMonth(maio).length, 2);

      await state.setHidden(transferencia, true);

      expect(state.isHidden(transferencia), isTrue);
      expect(state.cardSpentInMonth(maio), 10);
      // Continua aparecendo — riscado — para dar para conferir e desfazer.
      expect(state.cardEntriesForMonth(maio).length, 2);
      expect(state.hiddenCount, 1);
      expect(state.hiddenCountInMonth(maio), 1);
    });

    test('ocultar tira a categoria inteira da distribuição', () async {
      expect(state.categoryBreakdown(maio).length, 2);
      await state.setHidden(transferencia, true);

      final categorias = state.categoryBreakdown(maio);
      expect(categorias.length, 1);
      expect(categorias.single.label, SpendCategories.mercado);
      expect(categorias.single.share, 1.0);
    });

    test('o extrato continua mostrando o oculto, fora das contas', () async {
      await state.setHidden(transferencia, true);

      // Visível na lista…
      expect(state.entries.length, 2);
      expect(state.entries.any((e) => state.isHidden(e)), isTrue);
      // …e sem peso nenhum nos números.
      expect(state.cardSpentInMonth(maio), 10);
      expect(state.categoryBreakdown(maio).length, 1);
    });

    test('restaurar todos devolve tudo de uma vez', () async {
      await state.setHidden(transferencia, true);
      await state.setHidden(mercado, true);
      expect(state.hiddenCount, 2);
      expect(state.cardSpentInMonth(maio), 0);

      await state.clearHidden();
      expect(state.hiddenCount, 0);
      expect(state.cardSpentInMonth(maio), 1000);
    });

    test('restaurar devolve o gasto aos totais', () async {
      await state.setHidden(transferencia, true);
      await state.setHidden(transferencia, false);

      expect(state.isHidden(transferencia), isFalse);
      expect(state.cardSpentInMonth(maio), 1000);
      expect(state.hiddenCount, 0);
    });

    test('ocultar atinge só aquela transação, não o estabelecimento', () async {
      final outraNoMesmoLugar =
          compraEm('m2', 'MERCADINHO DO TICO', 25, maio);
      state.seedEntries([transferencia, mercado, outraNoMesmoLugar]);

      await state.setHidden(mercado, true);

      expect(state.isHidden(mercado), isTrue);
      expect(state.isHidden(outraNoMesmoLugar), isFalse);
      expect(state.cardSpentInMonth(maio), 1015);
    });
  });

  test('alocação soma a mesma moeda das duas carteiras numa fatia só', () {
    final state = AppState()
      ..snapshot = WalletSnapshot.fromJson({
        'accountType': 'UNIFIED',
        'totalEquity': '10',
        'totalWalletBalance': '10',
        'totalAvailableBalance': '10',
        'totalPerpUPL': '0',
        'coin': [
          {'coin': 'BRL', 'walletBalance': '5', 'equity': '5', 'usdValue': '1'},
          {'coin': 'USDT', 'walletBalance': '2', 'equity': '2', 'usdValue': '2'},
        ],
      })
      ..fundingCoins = [
        CoinBalance.fromFunding({'coin': 'BRL', 'walletBalance': '50'})
            .withUsdValue(9),
      ];

    // Nas duas carteiras BRL aparece separado, para dizer onde está o dinheiro.
    expect(state.allCoins.where((c) => c.coin == 'BRL').length, 2);

    // Já na alocação vira uma fatia só.
    final alocacao = state.allocationByCoin;
    expect(alocacao.where((e) => e.key == 'BRL').length, 1);
    expect(alocacao.first.key, 'BRL');
    expect(alocacao.first.value, 10);
    expect(alocacao.length, 2);
  });

  test('WalletSnapshot ordena moedas por valor em dólar', () {
    final snapshot = WalletSnapshot.fromJson({
      'accountType': 'UNIFIED',
      'totalEquity': '1000',
      'totalWalletBalance': '900',
      'totalAvailableBalance': '800',
      'totalPerpUPL': '10',
      'coin': [
        {'coin': 'USDT', 'walletBalance': '50', 'equity': '50', 'usdValue': '50'},
        {'coin': 'BTC', 'walletBalance': '0.01', 'equity': '0.01', 'usdValue': '900'},
      ],
    });
    expect(snapshot.coins.first.coin, 'BTC');
    expect(snapshot.activeCoins.length, 2);
  });
}
