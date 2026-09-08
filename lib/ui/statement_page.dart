import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/common.dart';
import 'widgets/entry_editor.dart';
import 'widgets/ledger_tile.dart';
import 'widgets/merchant_avatar.dart';

/// Extrato completo, com busca e filtros.
///
/// No celular é uma lista agrupada por dia. No computador vira tabela, com
/// colunas, seleção em massa e um painel de detalhes ao lado — na tela grande
/// cabe tudo de uma vez, sem precisar abrir e fechar folha a cada lançamento.
class StatementPage extends StatefulWidget {
  const StatementPage({super.key, required this.state});

  final AppState state;

  /// A partir daqui as colunas da tabela cabem.
  static const larguraDaTabela = 860.0;

  /// E a partir daqui ainda sobra espaço para o painel de detalhes ao lado.
  /// Abaixo disso o detalhe volta a abrir como folha, que é o que cabe.
  static const larguraDoPainel = 1040.0;

  static const _larguraDoPainelLateral = 340.0;

  @override
  State<StatementPage> createState() => _StatementPageState();
}

class _StatementPageState extends State<StatementPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// Lançamento aberto no painel lateral.
  String? _selecionado;

  /// Mostra o mês escolhido, ou o extrato inteiro.
  ///
  /// Começa no mês, como as outras páginas; procurar uma compra antiga é o
  /// caso em que se abre tudo, e o botão para isso fica ao lado do mês.
  bool _apenasDoMes = true;

  /// Marcados pelas caixinhas, para as ações em massa.
  final _marcados = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.state.search;
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Carrega a próxima página ao chegar perto do fim.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      widget.state.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final mes = state.selectedMonth;
    final entries = _apenasDoMes
        ? state.entries
            .where((e) => e.time.year == mes.year && e.time.month == mes.month)
            .toList()
        : state.entries;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabela = constraints.maxWidth >= StatementPage.larguraDaTabela;
        final cabePainel = constraints.maxWidth >= StatementPage.larguraDoPainel;
        if (!cabePainel && _selecionado != null) _selecionado = null;

        final selecionada = _selecionado == null
            ? null
            : entries.where((e) => e.id == _selecionado).firstOrNull;

        final lista = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: MonthPicker(
                state: state,
                enabled: _apenasDoMes,
                trailing: _BotaoTudo(
                  ativo: !_apenasDoMes,
                  onTap: () => setState(() => _apenasDoMes = !_apenasDoMes),
                ),
              ),
            ),
            _Ferramentas(
              state: state,
              controller: _searchController,
              compacto: tabela,
            ),
            if (tabela && state.uncategorizedCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _AvisoSemCategoria(state: state),
              ),
            if (_marcados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _BarraDeSelecao(
                  state: state,
                  marcados: _marcados
                      .map((id) => entries.where((e) => e.id == id).firstOrNull)
                      .whereType<LedgerEntry>()
                      .toList(),
                  onLimpar: () => setState(_marcados.clear),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _vazio(state)
                  : tabela
                      ? _tabela(entries,
                          cabePainel: cabePainel,
                          compacta: selecionada != null)
                      : _listaDoCelular(entries),
            ),
          ],
        );

        if (selecionada == null) return lista;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: lista),
            const SizedBox(width: 16),
            SizedBox(
              width: StatementPage._larguraDoPainelLateral,
              child: _PainelDeDetalhes(
                entry: selecionada,
                state: state,
                onFechar: () => setState(() => _selecionado = null),
              ),
            ),
            const SizedBox(width: 16),
          ],
        );
      },
    );
  }

  Widget _vazio(AppState state) {
    // Com o mês ligado, o vazio quase sempre é o mês errado — e não a falta
    // de dados. O caminho de saída é ver tudo, não atualizar.
    if (_apenasDoMes) {
      return EmptyState(
        icon: Icons.event_busy_rounded,
        title: 'Nada em ${fmtMonthYear(state.selectedMonth)}',
        message: state.search.isNotEmpty || state.filter != LedgerFilter.all
            ? 'Nenhum lançamento deste mês corresponde à busca ou ao filtro.'
            : 'Nenhuma movimentação neste mês. Veja outro mês ou o extrato '
                'inteiro.',
        action: FilledButton.icon(
          onPressed: () => setState(() => _apenasDoMes = false),
          icon: const Icon(Icons.all_inclusive_rounded, size: 18),
          label: const Text('Ver todos os meses'),
        ),
      );
    }

    return EmptyState(
      icon: Icons.receipt_long_rounded,
      title: 'Nada por aqui',
      message: state.search.isNotEmpty || state.filter != LedgerFilter.all
          ? 'Nenhum lançamento corresponde à busca ou ao filtro selecionado.'
          : 'Ainda não há movimentações nesta conta da Bybit.',
      action: FilledButton(
        onPressed: state.refresh,
        child: const Text('Atualizar'),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Computador: tabela
  // ---------------------------------------------------------------------

  Widget _tabela(
    List<LedgerEntry> entries, {
    required bool cabePainel,
    required bool compacta,
  }) {
    final state = widget.state;
    final todosMarcados =
        entries.isNotEmpty && _marcados.length == entries.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _CabecalhoDaTabela(
              compacta: compacta,
              todosMarcados: todosMarcados,
              onMarcarTodos: (marcar) => setState(() {
                _marcados.clear();
                if (marcar) _marcados.addAll(entries.map((e) => e.id));
              }),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                itemCount: entries.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == entries.length) return _footer(context, state);
                  final entry = entries[i];
                  return _LinhaDaTabela(
                    entry: entry,
                    state: state,
                    compacta: compacta,
                    selecionada: _selecionado == entry.id,
                    marcada: _marcados.contains(entry.id),
                    onMarcar: (marcar) => setState(() {
                      if (marcar) {
                        _marcados.add(entry.id);
                      } else {
                        _marcados.remove(entry.id);
                      }
                    }),
                    // Sem espaço para o painel, o detalhe abre como folha —
                    // é o mesmo conteúdo, no lugar que cabe.
                    onAbrir: () => cabePainel
                        ? setState(
                            () => _selecionado =
                                _selecionado == entry.id ? null : entry.id,
                          )
                        : showLedgerDetails(context, state: state, entry: entry),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Celular: lista agrupada por dia
  // ---------------------------------------------------------------------

  Widget _listaDoCelular(List<LedgerEntry> entries) {
    final rows = _buildRows(entries);
    return RefreshIndicator(
      onRefresh: widget.state.refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == rows.length) return _footer(context, widget.state);
          final row = rows[i];
          if (row.header != null) {
            return _DayHeader(label: row.header!, total: row.dayTotalLabel);
          }
          return LedgerTile(entry: row.entry!, state: widget.state);
        },
      ),
    );
  }

  Widget _footer(BuildContext context, AppState state) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: OutlinedButton(
            onPressed: state.loadMore,
            child: const Text('Carregar mais'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text('Fim do extrato', style: context.texts.bodySmall),
      ),
    );
  }

  /// Intercala cabeçalhos de dia entre os lançamentos.
  List<_Row> _buildRows(List<LedgerEntry> entries) {
    final rows = <_Row>[];
    String? currentDay;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final key = dayKey(entry.time);
      if (key != currentDay) {
        currentDay = key;
        // Transferências entre carteiras próprias e lançamentos ocultos não
        // entram no total do dia.
        final dayEntries = entries.where((e) =>
            dayKey(e.time) == key &&
            !e.neutral &&
            !widget.state.isHidden(e));
        final net = dayEntries.fold<double>(
          0,
          (sum, e) => sum + widget.state.usdValueOf(e.coin, e.change),
        );
        rows.add(_Row.header(
          fmtDayLabel(entry.time),
          net.abs() < 0.005
              ? null
              : '${net > 0 ? '+' : '−'}${fmtFiat(widget.state.toDisplay(net.abs()), brl: widget.state.showInBrl)}',
        ));
      }
      rows.add(_Row.entry(entry));
    }
    return rows;
  }
}

/// Solta o extrato do mês escolhido e mostra tudo o que já foi carregado.
class _BotaoTudo extends StatelessWidget {
  const _BotaoTudo({required this.ativo, required this.onTap});

  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ativo ? 'Voltar a filtrar por mês' : 'Ver todos os meses',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // Só o ícone: a faixa de filtros logo abaixo já tem um "Tudo", que é
        // dos tipos de lançamento. Dois botões com o mesmo nome e sentidos
        // diferentes na mesma tela seria pedir para errar.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: ativo ? AppColors.accent.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: ativo ? AppColors.accent : context.tones.border,
            ),
          ),
          child: Icon(
            Icons.all_inclusive_rounded,
            size: 18,
            color: ativo ? AppColors.accent : context.tones.muted,
          ),
        ),
      ),
    );
  }
}

/// Busca e filtros, no topo das duas formas de lista.
class _Ferramentas extends StatelessWidget {
  const _Ferramentas({
    required this.state,
    required this.controller,
    required this.compacto,
  });

  final AppState state;
  final TextEditingController controller;

  /// No computador a busca e os filtros dividem a mesma linha.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final busca = TextField(
      controller: controller,
      onChanged: state.setSearch,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar no extrato',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: compacto,
        contentPadding: compacto
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
            : null,
        suffixIcon: state.search.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  state.setSearch('');
                },
              ),
      ),
    );

    final filtros = SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: compacto ? 0 : 16),
        itemCount: LedgerFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = LedgerFilter.values[i];
          final selected = state.filter == f;
          return ChoiceChip(
            label: Text(ledgerFilterLabel(f)),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => state.setFilter(f),
            labelStyle: context.texts.bodySmall?.copyWith(
              color: selected ? AppColors.accent : context.tones.muted,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: context.colors.surface,
            selectedColor: AppColors.accent.withValues(alpha: 0.14),
            side: BorderSide(
              color: selected ? AppColors.accent : context.tones.border,
            ),
          );
        },
      ),
    );

    if (!compacto) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: busca,
          ),
          filtros,
          const SizedBox(height: 8),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          SizedBox(width: 320, child: busca),
          const SizedBox(width: 16),
          Expanded(child: filtros),
        ],
      ),
    );
  }
}

/// Chamada para resolver as compras que ficaram sem categoria.
class _AvisoSemCategoria extends StatelessWidget {
  const _AvisoSemCategoria({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final quantas = state.uncategorizedCount;
    final jaFiltrando = state.filter == LedgerFilter.uncategorized;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.label_outline_rounded,
              size: 18, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: context.texts.bodyMedium,
                children: [
                  TextSpan(
                    text: '$quantas sem categoria',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: ' — marque várias de uma vez pelas caixinhas',
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => state.setFilter(
              jaFiltrando ? LedgerFilter.all : LedgerFilter.uncategorized,
            ),
            child: Text(jaFiltrando ? 'Ver tudo' : 'Resolver agora →'),
          ),
        ],
      ),
    );
  }
}

/// Ações que valem para todos os lançamentos marcados.
class _BarraDeSelecao extends StatelessWidget {
  const _BarraDeSelecao({
    required this.state,
    required this.marcados,
    required this.onLimpar,
  });

  final AppState state;
  final List<LedgerEntry> marcados;
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    // Categoria só faz sentido em compra do cartão.
    final compras = marcados.where((e) => e.isCard).toList();
    final todosOcultos = marcados.every(state.isHidden);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: context.tones.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.tones.border),
      ),
      child: Row(
        children: [
          Text(
            '${marcados.length} '
            '${marcados.length == 1 ? 'selecionado' : 'selecionados'}',
            style: context.texts.titleSmall,
          ),
          const Spacer(),
          if (compras.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Definir categoria',
              onSelected: (categoria) async {
                for (final e in compras) {
                  await state.setEntryOverrides(e, category: categoria);
                }
                onLimpar();
              },
              itemBuilder: (_) => [
                for (final c in state.availableCategories)
                  PopupMenuItem<String>(
                    value: c,
                    child: Row(
                      children: [
                        Icon(categoryIcon(c), size: 17),
                        const SizedBox(width: 10),
                        Text(c),
                      ],
                    ),
                  ),
              ],
              child: _acao(
                context,
                Icons.label_outline_rounded,
                'Categorizar ${compras.length}',
              ),
            ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () async {
              for (final e in marcados) {
                await state.setHidden(e, !todosOcultos);
              }
              onLimpar();
            },
            icon: Icon(
              todosOcultos
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
            label: Text(todosOcultos ? 'Voltar aos totais' : 'Tirar dos totais'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Limpar seleção',
            onPressed: onLimpar,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _acao(BuildContext context, IconData icone, String texto) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              texto,
              style: context.texts.bodyMedium
                  ?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

/// Larguras das colunas, compartilhadas pelo cabeçalho e pelas linhas.
///
/// Com o painel aberto a tabela perde uns 350 pixels: a situação sai de cena
/// e a categoria encolhe, para a descrição continuar legível.
class _Colunas {
  static const marcar = 44.0;
  static const data = 92.0;
  static const valor = 132.0;

  static double categoria(bool compacta) => compacta ? 148 : 190;
  static double status(bool compacta) => compacta ? 0 : 116;
}

class _CabecalhoDaTabela extends StatelessWidget {
  const _CabecalhoDaTabela({
    required this.compacta,
    required this.todosMarcados,
    required this.onMarcarTodos,
  });

  final bool compacta;
  final bool todosMarcados;
  final ValueChanged<bool> onMarcarTodos;

  @override
  Widget build(BuildContext context) {
    Widget rotulo(String texto, {TextAlign align = TextAlign.left}) => Text(
          texto,
          style: context.texts.labelSmall,
          textAlign: align,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
      child: Row(
        children: [
          SizedBox(
            width: _Colunas.marcar,
            child: Checkbox(
              value: todosMarcados,
              onChanged: (v) => onMarcarTodos(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
          ),
          SizedBox(width: _Colunas.data, child: rotulo('DATA ↓')),
          Expanded(child: rotulo('DESCRIÇÃO')),
          SizedBox(
            width: _Colunas.categoria(compacta),
            child: rotulo('CATEGORIA'),
          ),
          if (!compacta)
            SizedBox(width: _Colunas.status(false), child: rotulo('STATUS')),
          SizedBox(
            width: _Colunas.valor,
            child: rotulo('VALOR', align: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _LinhaDaTabela extends StatelessWidget {
  const _LinhaDaTabela({
    required this.entry,
    required this.state,
    required this.compacta,
    required this.selecionada,
    required this.marcada,
    required this.onMarcar,
    required this.onAbrir,
  });

  final LedgerEntry entry;
  final AppState state;
  final bool compacta;
  final bool selecionada;
  final bool marcada;
  final ValueChanged<bool> onMarcar;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final oculto = state.isHidden(entry);

    final titulo = entry.isCard && entry.note != null
        ? state.displayNameOf(entry)
        : kindLabel(entry.kind, entry.rawType);

    final complemento = [
      if (entry.neutral) 'transferência interna · fora dos totais',
      if (!entry.neutral && !entry.isCard && entry.note != null) entry.note!,
      if (entry.symbol != null) entry.symbol!,
      if (oculto) 'fora dos totais',
    ].join(' · ');

    final cor = entry.neutral || entry.change == 0
        ? tones.muted
        : (entry.isIn ? tones.positive : tones.negative);

    return Material(
      color: selecionada
          ? AppColors.accent.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onAbrir,
        onLongPress: entry.isCard
            ? () => showEntryEditor(context, state: state, entry: entry)
            : null,
        child: Opacity(
          opacity: oculto ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
            child: Row(
              children: [
                SizedBox(
                  width: _Colunas.marcar,
                  child: Checkbox(
                    value: marcada,
                    onChanged: (v) => onMarcar(v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(
                  width: _Colunas.data,
                  child: Text(
                    fmtCompactDate(entry.time),
                    style: context.texts.bodyMedium?.copyWith(color: tones.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      MerchantAvatar(entry: entry, state: state, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titulo,
                              style: context.texts.titleSmall?.copyWith(
                                decoration:
                                    oculto ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (complemento.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                complemento,
                                style: context.texts.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                SizedBox(
                  width: _Colunas.categoria(compacta),
                  child: _Categoria(entry: entry, state: state),
                ),
                if (!compacta)
                  SizedBox(
                    width: _Colunas.status(false),
                    child: _Situacao(entry: entry),
                  ),
                SizedBox(
                  width: _Colunas.valor,
                  child: Text(
                    state.hideBalances
                        ? '•••••'
                        : state.formatValue(entry.change, entry.coin,
                            signed: !entry.neutral),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleSmall?.copyWith(
                      color: oculto ? tones.muted : cor,
                      decoration: oculto ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Célula da categoria. Sem classificação, vira o convite para dar uma.
class _Categoria extends StatelessWidget {
  const _Categoria({required this.entry, required this.state});

  final LedgerEntry entry;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!entry.isCard) {
      return Row(
        children: [
          Icon(Icons.swap_horiz_rounded, size: 15, color: context.tones.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.neutral ? 'Transferência' : kindLabel(entry.kind, entry.rawType),
              style: context.texts.bodyMedium?.copyWith(
                color: context.tones.muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (state.isUncategorized(entry)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showEntryEditor(context, state: state, entry: entry),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('categorizar'),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }

    final categoria = state.categoryOf(entry);
    return Row(
      children: [
        Icon(categoryIcon(categoria), size: 15, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            categoria,
            style: context.texts.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Célula da situação: paga, concluída, interna.
class _Situacao extends StatelessWidget {
  const _Situacao({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;

    final (texto, icone, cor) = switch (entry) {
      final e when e.neutral => ('Interna', Icons.swap_vert_rounded, tones.muted),
      final e when e.status != null => (
          e.status!,
          Icons.check_circle_outline_rounded,
          tones.muted,
        ),
      final e when e.kind == LedgerKind.cardPurchase => (
          'Pago',
          Icons.check_circle_outline_rounded,
          tones.muted,
        ),
      final e when e.kind == LedgerKind.cardRefund => (
          'Estornado',
          Icons.replay_rounded,
          tones.positive,
        ),
      _ => ('Concluído', Icons.check_circle_outline_rounded, tones.muted),
    };

    return Row(
      children: [
        Icon(icone, size: 15, color: cor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: context.texts.bodyMedium?.copyWith(color: cor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Painel lateral do computador com os detalhes do lançamento aberto.
class _PainelDeDetalhes extends StatelessWidget {
  const _PainelDeDetalhes({
    required this.entry,
    required this.state,
    required this.onFechar,
  });

  final LedgerEntry entry;
  final AppState state;
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 16, color: context.tones.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Detalhes', style: context.texts.labelSmall),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: onFechar,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: LedgerDetails(entry: entry, state: state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  _Row.header(this.header, this.dayTotalLabel) : entry = null;
  _Row.entry(this.entry)
      : header = null,
        dayTotalLabel = null;

  final String? header;
  final String? dayTotalLabel;
  final LedgerEntry? entry;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, this.total});

  final String label;
  final String? total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6, left: 4, right: 4),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: context.texts.labelSmall),
          const Spacer(),
          if (total != null)
            Text(
              total!,
              style: context.texts.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
