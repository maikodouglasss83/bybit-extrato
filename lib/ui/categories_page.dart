import 'package:flutter/material.dart';

import '../app_state.dart';
import '../budget.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/charts.dart';
import 'widgets/common.dart';
import 'widgets/entry_editor.dart';
import 'widgets/ledger_tile.dart';
import 'widgets/side_panel.dart';

/// Gastos do cartão distribuídos por categoria, mês a mês.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mes = state.selectedMonth;
    // Primeiro nível: as categorias principais. As subcategorias somam dentro
    // delas e aparecem ao tocar.
    final categorias = state.mainCategoryBreakdown(mes);
    final total = state.cardSpentInMonth(mes);
    final anterior = state.cardSpentInMonth(DateTime(mes.year, mes.month - 1));
    final moeda = state.cardCurrency;

    if (state.cardEntries.isEmpty) {
      return EmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: 'Sem compras no cartão',
        message: 'Assim que houver compras no Bybit Card, a distribuição por '
            'categoria aparece aqui.',
        action: FilledButton(
          onPressed: state.refresh,
          child: const Text('Atualizar'),
        ),
      );
    }

    final pagina = RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          MonthPicker(state: state),
          const SizedBox(height: 16),
          _TotalCard(
            state: state,
            total: total,
            anterior: anterior,
            moeda: moeda,
            compras: state
                .cardEntriesForMonth(mes)
                .where((e) => !state.isHidden(e))
                .length,
            ocultos: state.hiddenCountInMonth(mes),
            hidden: state.hideBalances,
          ),
          const SizedBox(height: 16),
          if (categorias.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'Nenhuma compra em ${fmtMonthYear(mes)}.',
                    style: context.texts.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else ...[
            _DistributionCard(categorias: categorias, moeda: moeda, state: state),
            const SizedBox(height: 16),
            _CategoryList(categorias: categorias, moeda: moeda, state: state),
          ],
          if (state.canLoadMoreCard) ...[
            const SizedBox(height: 16),
            _LoadHistoryCard(state: state),
          ],
        ],
      ),
    );

    return PainelLateral(child: pagina);
  }
}

/// Total do mês e comparação com o mês anterior.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.state,
    required this.total,
    required this.anterior,
    required this.moeda,
    required this.compras,
    required this.ocultos,
    required this.hidden,
  });

  final AppState state;
  final double total;
  final double anterior;
  final String moeda;
  final int compras;
  final int ocultos;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final diferenca = total - anterior;
    final temComparacao = anterior > 0;
    final subiu = diferenca > 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Total gasto no mês'),
          MaskedValue(
            hidden: hidden,
            maskLength: 8,
            value: state.formatValue(total, moeda, signed: false),
            style: context.texts.displaySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.shopping_bag_outlined, size: 15, color: tones.muted),
              const SizedBox(width: 6),
              Text('$compras compras', style: context.texts.bodySmall),
              if (temComparacao) ...[
                const SizedBox(width: 14),
                Icon(
                  subiu ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 15,
                  color: subiu ? tones.negative : tones.positive,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    hidden
                        ? '••••'
                        : '${subiu ? '+' : '−'}${state.formatValue(diferenca.abs(), moeda, signed: false)} '
                            'vs. mês anterior',
                    style: context.texts.bodySmall?.copyWith(
                      color: subiu ? tones.negative : tones.positive,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (ocultos > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.visibility_off_rounded, size: 14, color: tones.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$ocultos ${ocultos == 1 ? 'gasto oculto' : 'gastos ocultos'} '
                    'fora desta conta',
                    style: context.texts.bodySmall,
                    overflow: TextOverflow.ellipsis,
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

/// Rosca com a divisão do gasto entre as categorias.
class _DistributionCard extends StatefulWidget {
  const _DistributionCard({
    required this.categorias,
    required this.moeda,
    required this.state,
  });

  final List<CategoryTotal> categorias;
  final String moeda;
  final AppState state;

  @override
  State<_DistributionCard> createState() => _DistributionCardState();
}

class _DistributionCardState extends State<_DistributionCard> {
  /// Fatia destacada, compartilhada entre a rosca e a legenda.
  final _destaque = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _destaque.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categorias = widget.categorias;
    final state = widget.state;

    // Acima de oito fatias o gráfico vira sopa: o excedente vira "Outras".
    final visiveis = categorias.take(7).toList();
    final resto = categorias.skip(7).fold<double>(0, (sum, c) => sum + c.total);

    final slices = <Slice>[
      for (var i = 0; i < visiveis.length; i++)
        // A cor é da categoria, não da posição: a fatia de Transporte é azul
        // no mês em que ela lidera e no mês em que ela é a última.
        Slice(
          visiveis[i].label,
          visiveis[i].total,
          mainCategoryColor(visiveis[i].id ?? ''),
        ),
      if (resto > 0) Slice('Demais categorias', resto, context.tones.muted),
    ];

    final legendas = <(Color, String, String)>[
      for (var i = 0; i < visiveis.length; i++)
        (
          mainCategoryColor(visiveis[i].id ?? ''),
          visiveis[i].label,
          fmtPercent(visiveis[i].share),
        ),
      if (resto > 0)
        (
          context.tones.muted,
          'Demais categorias',
          fmtPercent(
            resto / categorias.fold<double>(0, (s, c) => s + c.total),
          ),
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Distribuição'),
          Center(
            child: DonutChart(
              slices: slices,
              size: 190,
              centerTop: 'CATEGORIAS',
              centerBottom: '${categorias.length}',
              destaque: _destaque,
              detalhe: (i) => state.hideBalances
                  ? '••••'
                  : state.formatValue(slices[i].value, widget.moeda,
                      signed: false),
            ),
          ),
          const SizedBox(height: 20),
          // A legenda destaca a mesma fatia: passar o mouse ou tocar num nome
          // acende a parte dele no gráfico.
          ValueListenableBuilder<int?>(
            valueListenable: _destaque,
            builder: (context, destacada, _) => Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (var i = 0; i < legendas.length; i++)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => _destaque.value = i,
                    onExit: (_) {
                      if (_destaque.value == i) _destaque.value = null;
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _destaque.value =
                          _destaque.value == i ? null : i,
                      child: _Legend(
                        color: legendas[i].$1,
                        label: legendas[i].$2,
                        value: legendas[i].$3,
                        apagada: destacada != null && destacada != i,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
    this.apagada = false,
  });

  final Color color;
  final String label;
  final String value;

  /// Outra fatia está em destaque.
  final bool apagada;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: apagada ? 0.4 : 1,
      child: _conteudo(context),
    );
  }

  Widget _conteudo(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: context.texts.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: context.texts.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Ranking de categorias; tocar em uma abre as compras dela.
class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categorias,
    required this.moeda,
    required this.state,
  });

  final List<CategoryTotal> categorias;
  final String moeda;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final maior = categorias.first.total;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Por categoria',
            trailing: Tooltip(
              message: 'Toque para ver as compras. Segure uma compra para '
                  'renomear ou trocar a categoria.',
              child: Icon(Icons.info_outline_rounded,
                  size: 15, color: context.tones.muted),
            ),
          ),
          for (var i = 0; i < categorias.length; i++)
            _CategoryRow(
              categoria: categorias[i],
              color: mainCategoryColor(categorias[i].id ?? ''),
              proporcao: maior == 0 ? 0 : categorias[i].total / maior,
              moeda: moeda,
              state: state,
            ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.categoria,
    required this.color,
    required this.proporcao,
    required this.moeda,
    required this.state,
  });

  final CategoryTotal categoria;
  final Color color;
  final double proporcao;
  final String moeda;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _abrirCompras(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    mainCategoryIcon(categoria.id ?? ''),
                    size: 17,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    categoria.label,
                    style: context.texts.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                MaskedValue(
                  hidden: state.hideBalances,
                  maskLength: 5,
                  value: state.formatValue(categoria.total, moeda, signed: false),
                  style: context.texts.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              // A barra ocupa a largura toda e o resumo vem embaixo: assim
              // todas as categorias começam e terminam no mesmo ponto, e dá
              // para comparar o tamanho delas de relance.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: proporcao.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: context.tones.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${categoria.count} ${categoria.count == 1 ? 'lançamento' : 'lançamentos'}',
                        style: context.texts.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        fmtPercent(categoria.share),
                        style: context.texts.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirCompras(BuildContext context) {
    // Folhas e painel ficam fora da árvore que escuta o estado, então
    // observam o AppState para refletir renomeações e trocas de categoria
    // assim que elas acontecem.
    Widget detalhe(ScrollController? rolagem) => AnimatedBuilder(
          animation: state,
          builder: (_, __) => _ComprasDaCategoria(
            state: state,
            categoria: categoria,
            color: color,
            moeda: moeda,
            rolagem: rolagem,
          ),
        );

    // No computador, ao lado da lista, como os detalhes do extrato.
    final noPainel = PainelLateral.abrir(
      context,
      titulo: 'Categoria',
      icone: Icons.pie_chart_outline_rounded,
      conteudo: (_) => detalhe(null),
    );
    if (noPainel) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, scrollController) => detalhe(scrollController),
      ),
    );
  }
}

/// Subcategorias e compras de uma categoria principal no mês escolhido.
class _ComprasDaCategoria extends StatelessWidget {
  const _ComprasDaCategoria({
    required this.state,
    required this.categoria,
    required this.color,
    required this.moeda,
    this.rolagem,
  });

  final AppState state;
  final CategoryTotal categoria;
  final Color color;
  final String moeda;

  /// Da folha arrastável, no celular. No painel a lista rola sozinha.
  final ScrollController? rolagem;

  @override
  Widget build(BuildContext context) {
    // Recalculado a cada mudança: uma compra recategorizada sai daqui.
    final mainId = categoria.id ?? kUncategorizedId;
    final subcategorias =
        state.subcategoryBreakdown(state.selectedMonth, mainId);
    final total = subcategorias.fold<double>(0, (sum, s) => sum + s.total);
    final compras = subcategorias.fold<int>(0, (sum, s) => sum + s.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(mainCategoryIcon(categoria.id ?? ''),
                      size: 20, color: color),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      categoria.label,
                      style: context.texts.headlineSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${state.hideBalances ? '••••' : state.formatValue(total, moeda, signed: false)} · '
                '$compras ${compras == 1 ? 'compra' : 'compras'} · '
                '${fmtMonthYear(state.selectedMonth)}',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: subcategorias.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma compra restou nesta categoria.',
                      style: context.texts.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: rolagem,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: subcategorias.length,
                  itemBuilder: (_, i) => _SubcategoriaExpansivel(
                    state: state,
                    subcategoria: subcategorias[i],
                    color: color,
                    moeda: moeda,
                    // Com uma subcategoria só, não há o que escolher:
                    // as compras já aparecem abertas.
                    aberta: subcategorias.length == 1,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Uma subcategoria dentro da principal aberta: mostra o total e, ao tocar,
/// as compras que formam aquele valor.
class _SubcategoriaExpansivel extends StatelessWidget {
  const _SubcategoriaExpansivel({
    required this.state,
    required this.subcategoria,
    required this.color,
    required this.moeda,
    required this.aberta,
  });

  final AppState state;
  final CategoryTotal subcategoria;
  final Color color;
  final String moeda;
  final bool aberta;

  @override
  Widget build(BuildContext context) {
    final compras = state.purchasesOfSubcategory(
      state.selectedMonth,
      subcategoria.id ?? '',
    );

    // O ícone vem do nó do planejamento: a subcategoria pode reunir mais de
    // uma categoria de gasto, e é o nó que dá a identidade dela.
    final no = state.budgetNodeById(subcategoria.id ?? '');
    final origem = no?.sources.isNotEmpty ?? false ? no!.sources.first : null;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: aberta,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            // Categoria criada pelo usuário não tem ícone próprio: o desenho
            // sai do nome que ela recebeu — "Cursos" vira o chapéu de
            // formatura, e não o "..." de genérico.
            origem == null || state.isCustomCategory(origem)
                ? iconForCategoryName(subcategoria.label)
                : categoryIcon(origem),
            size: 17,
            color: color,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                subcategoria.label,
                style: context.texts.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              state.hideBalances
                  ? '••••'
                  : state.formatValue(subcategoria.total, moeda, signed: false),
              style: context.texts.titleSmall,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${fmtPercent(subcategoria.share)} da categoria · '
            '${subcategoria.count}x',
            style: context.texts.bodySmall,
          ),
        ),
        children: [
          for (final compra in compras)
            LedgerTile(
              entry: compra,
              state: state,
              onLongPress: () =>
                  showEntryEditor(context, state: state, entry: compra),
            ),
        ],
      ),
    );
  }
}

/// Convite para trazer os meses mais antigos.
class _LoadHistoryCard extends StatelessWidget {
  const _LoadHistoryCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final carregadas = state.cardEntries.length;
    final total = state.cardTotalCount;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Histórico completo', style: context.texts.titleSmall),
          const SizedBox(height: 6),
          Text(
            total > 0
                ? '$carregadas de $total compras carregadas. Traga o restante '
                    'para analisar meses anteriores.'
                : 'Carregue as compras mais antigas para analisar outros meses.',
            style: context.texts.bodySmall,
          ),
          const SizedBox(height: 16),
          if (state.loadingCardHistory)
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Carregando… $carregadas${total > 0 ? ' de $total' : ''}',
                  style: context.texts.bodySmall,
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: state.loadFullCardHistory,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Carregar histórico completo'),
            ),
        ],
      ),
    );
  }
}
