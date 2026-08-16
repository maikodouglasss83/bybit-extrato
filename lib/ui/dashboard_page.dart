import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/charts.dart';
import 'widgets/common.dart';
import 'widgets/ledger_tile.dart';

/// Visão geral: patrimônio, evolução, alocação e últimas movimentações.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.state,
    required this.onSeeStatement,
    this.onSeeCategories,
  });

  final AppState state;
  final VoidCallback onSeeStatement;
  final VoidCallback? onSeeCategories;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _BalanceHero(state: state),
          const SizedBox(height: 16),
          if (state.errorMessage != null) ...[
            ErrorBanner(message: state.errorMessage!, onRetry: state.refresh),
            const SizedBox(height: 16),
          ],
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _BalanceTrendCard(state: state)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _AllocationCard(state: state)),
                ],
              ),
            )
          else ...[
            _BalanceTrendCard(state: state),
            const SizedBox(height: 16),
            _AllocationCard(state: state),
          ],
          if (state.cardEntries.isNotEmpty || state.cardRewards.hasData) ...[
            const SizedBox(height: 16),
            _CardSpendingCard(state: state, onSeeAll: onSeeCategories),
          ],
          if (state.cardEntries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FixedVsVariableCard(state: state),
          ],
          const SizedBox(height: 16),
          _FlowCard(state: state),
          const SizedBox(height: 16),
          _AssetsCard(state: state),
          const SizedBox(height: 16),
          _RecentCard(state: state, onSeeAll: onSeeStatement),
        ],
      ),
    );
  }
}

/// Cartão principal com o patrimônio total.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final equityUsd = state.totalEquityUsd;
    final pnl = state.snapshot.totalPerpUPL;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tones.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.16),
            context.colors.surface,
            context.colors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('PATRIMÔNIO TOTAL', style: context.texts.labelSmall),
              ),
              IconButton(
                tooltip: state.hideBalances ? 'Mostrar valores' : 'Ocultar valores',
                onPressed: state.toggleHideBalances,
                icon: Icon(
                  state.hideBalances
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: tones.muted,
                ),
              ),
              if (state.usdBrl != null)
                _CurrencyToggle(state: state),
            ],
          ),
          const SizedBox(height: 6),
          MaskedValue(
            hidden: state.hideBalances,
            maskLength: 8,
            value: fmtFiat(state.toDisplay(equityUsd), brl: state.showInBrl),
            style: context.texts.displaySmall,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 28,
            runSpacing: 14,
            children: [
              _MiniStat(
                label: 'Disponível',
                value: fmtFiat(
                  state.toDisplay(state.totalAvailableUsd),
                  brl: state.showInBrl,
                ),
                hidden: state.hideBalances,
              ),
              _MiniStat(
                label: 'Conta unificada',
                value: fmtFiat(
                  state.toDisplay(state.snapshot.totalEquity),
                  brl: state.showInBrl,
                ),
                hidden: state.hideBalances,
              ),
              _MiniStat(
                label: 'Conta de fundos',
                value: fmtFiat(state.toDisplay(state.fundingUsd), brl: state.showInBrl),
                hidden: state.hideBalances,
              ),
              if (pnl != 0)
                _MiniStat(
                  label: 'Resultado aberto',
                  value: fmtFiat(state.toDisplay(pnl), brl: state.showInBrl),
                  hidden: state.hideBalances,
                  color: pnl > 0 ? tones.positive : tones.negative,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.sync_rounded, size: 14, color: tones.muted),
              const SizedBox(width: 6),
              Text(
                state.lastSync == null
                    ? 'Nunca sincronizado'
                    : 'Atualizado às ${fmtTime(state.lastSync!)}',
                style: context.texts.bodySmall,
              ),
              const Spacer(),
              Text(
                'Conta ${state.snapshot.accountType}',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrencyToggle extends StatelessWidget {
  const _CurrencyToggle({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: state.toggleCurrency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: context.tones.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.tones.border),
        ),
        child: Text(
          state.showInBrl ? 'BRL' : 'USD',
          style: context.texts.labelSmall?.copyWith(color: AppColors.accent),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.hidden,
    this.color,
  });

  final String label;
  final String value;
  final bool hidden;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.texts.bodySmall),
        const SizedBox(height: 4),
        MaskedValue(
          hidden: hidden,
          maskLength: 5,
          value: value,
          style: context.texts.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Evolução dos gastos mês a mês.
///
/// Substituiu um gráfico de saldo que dependia do extrato da conta unificada:
/// como as compras ficam todas no cartão, aquele campo vinha sempre vazio.
class _BalanceTrendCard extends StatelessWidget {
  const _BalanceTrendCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final meses = state.monthlySpending(months: state.monthlyRange);
    // A comparação sai do histórico inteiro, não do recorte: com "1 mês"
    // selecionado ainda faz sentido saber como foi o mês passado.
    final serieCheia = state.monthlySpending(months: 0);
    final moeda = state.cardCurrency;

    if (meses.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Evolução dos gastos'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Sem compras carregadas ainda.',
                  style: context.texts.bodySmall,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final atual = serieCheia.last.value;
    final anterior =
        serieCheia.length >= 2 ? serieCheia[serieCheia.length - 2].value : 0.0;
    final variacao = atual - anterior;
    final subiu = variacao > 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Evolução dos gastos',
            trailing: _RangePicker(state: state),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MaskedValue(
                hidden: state.hideBalances,
                maskLength: 6,
                value: state.formatValue(atual, moeda, signed: false),
                style: context.texts.headlineSmall,
              ),
              const SizedBox(width: 8),
              if (serieCheia.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    state.hideBalances
                        ? '•••'
                        : '${subiu ? '+' : '−'}'
                            '${state.formatValue(variacao.abs(), moeda, signed: false)}'
                            ' vs. mês anterior',
                    style: context.texts.bodySmall?.copyWith(
                      color: subiu ? tones.negative : tones.positive,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          MonthlyBars(
            values: [for (final m in meses) m.value],
            labels: [for (final m in meses) fmtMonthShort(m.key)],
            valueLabel: (v) => state.hideBalances
                ? '•••'
                : state.formatValue(v, moeda, signed: false),
          ),
          if (state.canLoadMoreCard) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.history_rounded, size: 14, color: tones.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Carregue o histórico completo em Gastos para ver mais meses.',
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Distribuição do patrimônio entre as moedas.
class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.state});

  final AppState state;

  static const _colors = [
    AppColors.accent,
    Color(0xFF627EEA),
    Color(0xFFF7931A),
    Color(0xFFA78BFA),
    Color(0xFF38BDF8),
    Color(0xFFF5A524),
  ];

  @override
  Widget build(BuildContext context) {
    // Junta as carteiras: a mesma moeda não deve virar duas fatias.
    final coins = state.allocationByCoin.take(6).toList();
    final total = coins.fold<double>(0, (sum, c) => sum + c.value);

    final slices = <Slice>[
      for (var i = 0; i < coins.length; i++)
        Slice(coins[i].key, coins[i].value, _colors[i % _colors.length]),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Alocação'),
          if (coins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Sem saldo para distribuir',
                  style: context.texts.bodySmall,
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DonutChart(
                  slices: slices,
                  size: 132,
                  centerTop: 'ATIVOS',
                  centerBottom: '${coins.length}',
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < coins.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _colors[i % _colors.length],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  coins[i].key,
                                  style: context.texts.titleSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                total == 0
                                    ? '—'
                                    : '${(coins[i].value / total * 100).toStringAsFixed(1)}%',
                                style: context.texts.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Gastos do Bybit Card no mês, divididos por categoria, mais os pontos.
class _CardSpendingCard extends StatelessWidget {
  const _CardSpendingCard({required this.state, this.onSeeAll});

  final AppState state;
  final VoidCallback? onSeeAll;

  static const _categoryColors = [
    AppColors.accent,
    Color(0xFF627EEA),
    Color(0xFFF5A524),
    Color(0xFFA78BFA),
    Color(0xFF38BDF8),
    Color(0xFFF4436B),
  ];

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final rewards = state.cardRewards;
    final categorias = state.cardCategoriesThisMonth;
    final gastoMes = state.cardSpentThisMonth;
    final moeda = state.cardCurrency;
    final maior = categorias.isEmpty ? 0.0 : categorias.first.value;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Bybit Card',
            trailing: onSeeAll == null
                ? Text(
                    '${state.cardEntries.length} compras',
                    style: context.texts.bodySmall,
                  )
                : TextButton(
                    onPressed: onSeeAll,
                    child: const Text('Ver gastos'),
                  ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gasto neste mês', style: context.texts.bodySmall),
                    const SizedBox(height: 4),
                    MaskedValue(
                      hidden: state.hideBalances,
                      maskLength: 7,
                      value: state.formatValue(gastoMes, moeda, signed: false),
                      style: context.texts.headlineSmall,
                    ),
                  ],
                ),
              ),
              if (rewards.hasData)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Pontos', style: context.texts.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      fmtPoints(rewards.availablePoints),
                      style: context.texts.headlineSmall
                          ?.copyWith(color: AppColors.accent),
                    ),
                    if (rewards.pendingPoints > 0)
                      Text(
                        '+${fmtPoints(rewards.pendingPoints)} a liberar',
                        style: context.texts.bodySmall,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          _TierGoal(state: state),
          if (rewards.limit > 0) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Cashback do mês', style: context.texts.bodySmall),
                const Spacer(),
                Text(
                  '${fmtPlain(rewards.usedLimit)} / ${fmtPlain(rewards.limit)} ${rewards.limitUnit}',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: rewards.limitProgress,
                minHeight: 8,
                backgroundColor: tones.surfaceAlt,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
          ],
          if (categorias.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 14),
            Text('Onde você gastou este mês', style: context.texts.titleSmall),
            const SizedBox(height: 14),
            for (var i = 0; i < categorias.take(5).length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            categorias[i].key,
                            style: context.texts.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        MaskedValue(
                          hidden: state.hideBalances,
                          maskLength: 5,
                          value: state.formatValue(categorias[i].value, moeda,
                              signed: false),
                          style: context.texts.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: maior == 0 ? 0 : categorias[i].value / maior,
                        minHeight: 6,
                        backgroundColor: tones.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation(
                          _categoryColors[i % _categoryColors.length],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Escolha do período mostrado no gráfico de evolução.
class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Período do gráfico',
      initialValue: state.monthlyRange,
      onSelected: state.setMonthlyRange,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final opcao in AppState.monthlyRangeOptions.entries)
          PopupMenuItem<int>(
            value: opcao.key,
            child: Row(
              children: [
                Icon(
                  opcao.key == state.monthlyRange
                      ? Icons.check_rounded
                      : Icons.remove,
                  size: 16,
                  color: opcao.key == state.monthlyRange
                      ? AppColors.accent
                      : Colors.transparent,
                ),
                const SizedBox(width: 10),
                Text(opcao.value),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: context.tones.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.tones.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.monthlyRangeLabel, style: context.texts.bodySmall),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded,
                size: 18, color: context.tones.muted),
          ],
        ),
      ),
    );
  }
}

/// Progresso rumo ao gasto que mantém o nível do cartão.
class _TierGoal extends StatelessWidget {
  const _TierGoal({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final bateu = state.cardGoalReached;
    final falta = state.cardGoalRemainingUsd;
    final dias = state.daysLeftInMonth;
    final cor = bateu ? tones.positive : AppColors.accent;

    return InkWell(
      onTap: () => _editarMeta(context),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  bateu ? Icons.verified_rounded : Icons.workspace_premium_outlined,
                  size: 16,
                  color: cor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nível Beta · 2% de cashback',
                    style: context.texts.titleSmall,
                  ),
                ),
                Icon(Icons.edit_outlined, size: 14, color: tones.muted),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MaskedValue(
                  hidden: state.hideBalances,
                  maskLength: 6,
                  value: fmtFiat(state.cardSpentUsdThisMonth, brl: false),
                  style: context.texts.headlineSmall?.copyWith(color: cor),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'de ${fmtFiat(state.cardGoalUsd, brl: false)}',
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: state.cardGoalProgress,
                minHeight: 10,
                backgroundColor: tones.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(cor),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              bateu
                  ? 'Meta batida! O nível está garantido neste mês.'
                  : state.hideBalances
                      ? 'Faltam •••• para manter o nível'
                      : 'Faltam ${fmtFiat(falta, brl: false)} para manter o nível'
                          ' · ${dias == 1 ? 'último dia' : '$dias dias restantes'}',
              style: context.texts.bodySmall?.copyWith(
                color: bateu ? tones.positive : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editarMeta(BuildContext context) async {
    final controller =
        TextEditingController(text: state.cardGoalUsd.toStringAsFixed(0));

    final valor = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Meta do nível'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quanto é preciso gastar por mês, em dólar, para manter o nível '
              'do cartão. A Bybit não informa esse valor pela API.',
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: r'US$ ',
                labelText: 'Meta mensal',
              ),
              onSubmitted: (t) => Navigator.of(dialogContext)
                  .pop(double.tryParse(t.replaceAll(',', '.'))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(double.tryParse(controller.text.replaceAll(',', '.'))),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (valor != null && valor > 0) await state.setCardGoal(valor);
  }
}

/// Quanto do mês é compromisso e quanto é escolha do dia a dia.
class _FixedVsVariableCard extends StatelessWidget {
  const _FixedVsVariableCard({required this.state});

  final AppState state;

  static const _corFixo = Color(0xFF627EEA);
  static const _corVariavel = AppColors.accent;

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    final mes = DateTime(agora.year, agora.month);
    final divisao = state.fixedVsVariable(mes);
    final total = divisao.fixo + divisao.variavel;
    final moeda = state.cardCurrency;
    final compromissos = state.fixedMerchants(mes);

    String valor(double v) =>
        state.hideBalances ? '••••' : state.formatValue(v, moeda, signed: false);

    if (total <= 0) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Fixo x variável'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Sem compras neste mês.',
                    style: context.texts.bodySmall),
              ),
            ),
          ],
        ),
      );
    }

    final fracaoFixa = divisao.fixo / total;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Fixo x variável',
            trailing: Tooltip(
              message: 'Segure uma compra no extrato para mudar o tipo.',
              child: Icon(Icons.info_outline_rounded,
                  size: 15, color: context.tones.muted),
            ),
          ),
          // Uma barra só, dividida: a proporção entre os dois é a leitura
          // que importa, mais do que os valores isolados.
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  // O peso precisa ser sempre pelo menos 1: uma fatia mínima
                  // arredondaria para zero e derrubaria a tela.
                  if (fracaoFixa > 0)
                    Expanded(
                      flex: math.max(1, (fracaoFixa * 1000).round()),
                      child: Container(color: _corFixo),
                    ),
                  if (fracaoFixa < 1)
                    Expanded(
                      flex: math.max(1, ((1 - fracaoFixa) * 1000).round()),
                      child: Container(color: _corVariavel),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Parte(
                  cor: _corFixo,
                  rotulo: 'Fixo',
                  valor: valor(divisao.fixo),
                  percentual: '${(fracaoFixa * 100).toStringAsFixed(0)}%',
                ),
              ),
              Expanded(
                child: _Parte(
                  cor: _corVariavel,
                  rotulo: 'Variável',
                  valor: valor(divisao.variavel),
                  percentual: '${((1 - fracaoFixa) * 100).toStringAsFixed(0)}%',
                ),
              ),
            ],
          ),
          if (compromissos.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 14),
            _Compromissos(state: state),
          ],
        ],
      ),
    );
  }
}

/// Compromissos do mês com a data prevista de cada um.
///
/// A previsão sai do próprio histórico — dia costumeiro e valor recente — e
/// serve para o mês não terminar com uma surpresa.
class _Compromissos extends StatelessWidget {
  const _Compromissos({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final agora = DateTime.now();
    final mes = DateTime(agora.year, agora.month);
    final previsoes = state.fixedForecast(mes);
    final moeda = state.cardCurrency;
    final falta = state.pendingFixedInMonth(mes);

    if (previsoes.isEmpty) return const SizedBox.shrink();

    String valor(double v) =>
        state.hideBalances ? '••••' : state.formatValue(v, moeda, signed: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Compromissos do mês', style: context.texts.titleSmall),
            ),
            if (falta > 0)
              Text(
                'faltam ${valor(falta)}',
                style: context.texts.bodySmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (final p in previsoes.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LinhaCompromisso(previsao: p, valor: valor(p.expectedAmount)),
          ),
        if (previsoes.length > 6)
          Text('e mais ${previsoes.length - 6}', style: context.texts.bodySmall),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 13, color: tones.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'As datas vêm do seu histórico: o dia em que cada um costuma '
                'cair.',
                style: context.texts.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LinhaCompromisso extends StatelessWidget {
  const _LinhaCompromisso({required this.previsao, required this.valor});

  final FixedForecast previsao;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;

    final (cor, icone, situacao) = switch (previsao) {
      final p when p.paid => (
          tones.positive,
          Icons.check_circle_rounded,
          'pago dia ${p.paidDate!.day}',
        ),
      final p when p.late => (
          tones.negative,
          Icons.error_outline_rounded,
          'previsto dia ${p.expectedDay} · ${-p.daysUntil}d atrás',
        ),
      final p when p.dueToday => (
          AppColors.warning,
          Icons.today_rounded,
          'previsto para hoje',
        ),
      final p when p.dueSoon => (
          AppColors.warning,
          Icons.schedule_rounded,
          'dia ${p.expectedDay} · em ${p.daysUntil}d',
        ),
      final p => (
          tones.muted,
          Icons.event_outlined,
          'previsto dia ${p.expectedDay}',
        ),
    };

    return Row(
      children: [
        Icon(icone, size: 17, color: cor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                previsao.merchant,
                style: context.texts.bodyMedium?.copyWith(
                  // O que já foi pago sai do caminho visualmente.
                  color: previsao.paid ? tones.muted : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                situacao,
                style: context.texts.bodySmall?.copyWith(
                  color: previsao.paid ? tones.muted : cor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              previsao.paid ? valor : '~$valor',
              style: context.texts.titleSmall?.copyWith(
                color: previsao.paid ? tones.muted : null,
              ),
            ),
            if (!previsao.paid && previsao.monthsSeen >= 3)
              Text('${previsao.monthsSeen} meses', style: context.texts.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _Parte extends StatelessWidget {
  const _Parte({
    required this.cor,
    required this.rotulo,
    required this.valor,
    required this.percentual,
  });

  final Color cor;
  final String rotulo;
  final String valor;
  final String percentual;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 8),
            Text(rotulo, style: context.texts.bodySmall),
            const SizedBox(width: 6),
            Text(
              percentual,
              style: context.texts.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(valor, style: context.texts.titleMedium),
      ],
    );
  }
}

/// Entradas x saídas dentro do que já foi carregado do extrato.
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    var inflow = 0.0;
    var outflow = 0.0;
    for (final e in state.entries) {
      if (e.neutral || state.isHidden(e)) continue;
      final usd = state.usdValueOf(e.coin, e.change.abs());
      if (usd <= 0) continue;
      if (e.change > 0) {
        inflow += usd;
      } else {
        outflow += usd;
      }
    }

    final net = inflow - outflow;
    final hidden = state.hideBalances;
    String money(double usd) =>
        hidden ? '••••' : fmtFiat(state.toDisplay(usd), brl: state.showInBrl);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Fluxo do período',
            trailing: Text(
              '${state.entries.length} lançamentos',
              style: context.texts.bodySmall,
            ),
          ),
          FlowBars(
            inflow: inflow,
            outflow: outflow,
            inflowLabel: money(inflow),
            outflowLabel: money(outflow),
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Resultado líquido', style: context.texts.bodyMedium),
              const Spacer(),
              Text(
                money(net),
                style: context.texts.titleMedium?.copyWith(
                  color: net >= 0 ? context.tones.positive : context.tones.negative,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lista de moedas com saldo.
class _AssetsCard extends StatelessWidget {
  const _AssetsCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final coins = state.allCoins;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Meus ativos'),
          if (coins.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text('Nenhuma moeda com saldo.', style: context.texts.bodySmall),
            )
          else
            for (final c in coins) _AssetRow(coin: c, state: state),
        ],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.coin, required this.state});

  final CoinBalance coin;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CoinBadge(coin: coin.coin),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(coin.coin, style: context.texts.titleSmall),
                const SizedBox(height: 2),
                MaskedValue(
                  hidden: state.hideBalances,
                  maskLength: 6,
                  value: '${fmtCrypto(coin.equity)} · ${accountLabel(coin.account)}',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MaskedValue(
                hidden: state.hideBalances,
                maskLength: 5,
                value: fmtFiat(state.toDisplay(coin.usdValue), brl: state.showInBrl),
                style: context.texts.titleSmall,
              ),
              if (coin.unrealisedPnl != 0) ...[
                const SizedBox(height: 2),
                Text(
                  '${coin.unrealisedPnl > 0 ? '+' : '−'}${fmtCrypto(coin.unrealisedPnl.abs())}',
                  style: context.texts.bodySmall?.copyWith(
                    color: coin.unrealisedPnl > 0
                        ? context.tones.positive
                        : context.tones.negative,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Prévia das últimas movimentações.
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.state, required this.onSeeAll});

  final AppState state;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final recent = state.entries.take(6).toList();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Últimas movimentações',
            trailing: TextButton(
              onPressed: onSeeAll,
              child: const Text('Ver extrato'),
            ),
          ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Nenhuma movimentação encontrada ainda.',
                style: context.texts.bodySmall,
              ),
            )
          else
            for (final e in recent) LedgerTile(entry: e, state: state),
        ],
      ),
    );
  }
}
