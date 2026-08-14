import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/common.dart';
import 'widgets/ledger_tile.dart';

/// Extrato completo, agrupado por dia, com busca e filtros.
class StatementPage extends StatefulWidget {
  const StatementPage({super.key, required this.state});

  final AppState state;

  @override
  State<StatementPage> createState() => _StatementPageState();
}

class _StatementPageState extends State<StatementPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

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
    final entries = state.entries;
    final rows = _buildRows(entries);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: state.setSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar por moeda, par ou tipo',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: state.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        state.setSearch('');
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
        ),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'Nada por aqui',
                  message: state.search.isNotEmpty || state.filter != LedgerFilter.all
                      ? 'Nenhum lançamento corresponde à busca ou ao filtro selecionado.'
                      : 'Ainda não há movimentações nesta conta da Bybit.',
                  action: FilledButton(
                    onPressed: state.refresh,
                    child: const Text('Atualizar'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: state.refresh,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: rows.length + 1,
                    itemBuilder: (context, i) {
                      if (i == rows.length) return _footer(context, state);
                      final row = rows[i];
                      if (row.header != null) {
                        return _DayHeader(label: row.header!, total: row.dayTotalLabel);
                      }
                      return LedgerTile(entry: row.entry!, state: state);
                    },
                  ),
                ),
        ),
      ],
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
