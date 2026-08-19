import 'package:flutter/material.dart';

import '../app_state.dart';
import '../budget.dart';
import '../theme.dart';
import '../util/categorizer.dart';
import '../util/format.dart';
import 'widgets/common.dart';

/// Planejamento financeiro: metas por categoria e subcategoria, comparadas
/// com o que já foi gasto no mês.
class PlanningPage extends StatelessWidget {
  const PlanningPage({super.key, required this.state});

  final AppState state;

  static const _cores = [
    AppColors.accent,
    Color(0xFF627EEA),
    Color(0xFFF5A524),
    Color(0xFFA78BFA),
    Color(0xFF38BDF8),
    Color(0xFFF4436B),
    Color(0xFF34D399),
    Color(0xFFFB923C),
  ];

  @override
  Widget build(BuildContext context) {
    final mes = state.selectedMonth;
    final linhas = state.budgetLines(mes);

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _MonthPicker(state: state),
          const SizedBox(height: 16),
          _Summary(state: state, month: mes),
          const SizedBox(height: 16),
          _CategoryList(state: state, linhas: linhas),
          const SizedBox(height: 8),
          // Depois de tudo, inclusive de "Sem categoria": criar categoria é
          // exceção, não a ação principal da tela.
          Center(
            child: TextButton.icon(
              onPressed: () => showBudgetNodeEditor(context, state: state),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Nova categoria'),
              style: TextButton.styleFrom(
                foregroundColor: context.tones.muted,
                textStyle: context.texts.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color colorFor(int i) => _cores[i % _cores.length];
}

/// Navegação entre meses, a mesma da tela de gastos.
class _MonthPicker extends StatelessWidget {
  const _MonthPicker({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => state.shiftMonth(-1),
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Mês anterior',
        ),
        Expanded(
          child: Text(
            fmtMonthYear(state.selectedMonth),
            textAlign: TextAlign.center,
            style: context.texts.titleMedium,
          ),
        ),
        IconButton(
          onPressed: state.canGoToNextMonth ? () => state.shiftMonth(1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Próximo mês',
        ),
      ],
    );
  }
}

/// Cartão do topo: gasto, meta e quanto resta.
class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.month});

  final AppState state;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final gasto = state.budgetSpentTotal(month);
    final meta = state.budgetTotal(month);
    final resta = meta - gasto;
    final estourou = meta > 0 && resta < 0;
    final progresso = meta <= 0 ? 0.0 : (gasto / meta).clamp(0.0, 1.0);
    final cor = estourou ? tones.negative : AppColors.accent;

    String valor(double v) => state.formatValue(v, 'BRL', signed: false);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tones.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cor.withValues(alpha: 0.16),
            context.colors.surface,
            context.colors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PLANEJADO NO MÊS', style: context.texts.labelSmall),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MaskedValue(
                hidden: state.hideBalances,
                maskLength: 7,
                value: valor(gasto),
                style: context.texts.displaySmall,
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  meta > 0 ? 'de ${valor(meta)}' : 'sem meta definida',
                  style: context.texts.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 10,
              backgroundColor: tones.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(cor),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Gasto',
                  value: valor(gasto),
                  hidden: state.hideBalances,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Meta',
                  value: meta > 0 ? valor(meta) : '—',
                  hidden: state.hideBalances,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: estourou ? 'Excedeu' : 'Resta',
                  value: meta > 0 ? valor(resta.abs()) : '—',
                  hidden: state.hideBalances,
                  color: meta <= 0
                      ? null
                      : (estourou ? tones.negative : tones.positive),
                ),
              ),
            ],
          ),
          if (meta <= 0) ...[
            const SizedBox(height: 14),
            Text(
              'Defina metas tocando nas categorias abaixo para acompanhar '
              'quanto ainda cabe gastar.',
              style: context.texts.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
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

/// Lista de categorias com as subcategorias dentro.
class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.state, required this.linhas});

  final AppState state;
  final List<BudgetLine> linhas;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SectionLabel('Gastos por categorias'),
          ),
          for (var i = 0; i < linhas.length; i++)
            _CategoryTile(
              state: state,
              linha: linhas[i],
              color: PlanningPage.colorFor(i),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.state,
    required this.linha,
    required this.color,
  });

  final AppState state;
  final BudgetLine linha;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;

    String valor(double v) =>
        state.hideBalances ? '••••' : state.formatValue(v, 'BRL', signed: false);

    return Theme(
      // A lista fica limpa sem as linhas divisórias do expansor.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        // Expande sempre: mesmo sem subcategorias, é lá dentro que se
        // define a meta.
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconFor(linha.node), size: 18, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                linha.node.name,
                style: context.texts.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              valor(linha.spent),
              style: context.texts.titleSmall?.copyWith(
                color: linha.exceeded ? tones.negative : null,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Meta e saldo na mesma linha: um embaixo do nome, o outro
              // embaixo do total, cada um sob o número a que se refere.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      linha.hasBudget
                          ? 'Meta: ${valor(linha.budget)}'
                          : 'Sem meta definida',
                      style: context.texts.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (linha.hasBudget)
                    Text(
                      linha.exceeded
                          ? 'Excedeu: ${valor(linha.remaining.abs())}'
                          : 'Resta: ${valor(linha.remaining)}',
                      style: context.texts.bodySmall?.copyWith(
                        color: linha.exceeded ? tones.negative : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: linha.progress,
                  minHeight: 6,
                  backgroundColor: tones.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(
                    linha.exceeded ? tones.negative : color,
                  ),
                ),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editarMeta(context, linha.node),
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: Text(
                  linha.hasBudget ? 'Editar meta' : 'Definir meta de gastos',
                ),
              ),
            ),
          ),
          for (final filho in linha.children)
            _SubcategoryTile(state: state, linha: filho, color: color),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showBudgetNodeEditor(
                  context,
                  state: state,
                  parentId: linha.node.id,
                  parentName: linha.node.name,
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Subcategoria'),
              ),
            ),
          ),
          if (state.canRemoveBudgetNode(linha.node))
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _apagar(context, linha.node),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Apagar categoria'),
                  style: TextButton.styleFrom(foregroundColor: tones.negative),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editarMeta(BuildContext context, BudgetNode node) =>
      showBudgetGoalDialog(context, state: state, node: node);

  Future<void> _apagar(BuildContext context, BudgetNode node) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Apagar "${node.name}"?'),
        content: const Text(
          'As subcategorias dela também são apagadas. Os gastos não somem: '
          'voltam para "Sem categoria".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok == true) await state.removeBudgetNode(node.id);
  }

  /// Principais usam o ícone do grupo; subcategorias, o da categoria de
  /// gasto que elas representam.
  static IconData _iconFor(BudgetNode node) {
    if (node.isMain) return mainCategoryIcon(node.id);
    if (node.sources.isEmpty) return Icons.bookmark_outline_rounded;

    final valor = node.sources.first;
    return SpendCategories.all.contains(valor)
        ? categoryIcon(valor)
        : Icons.bookmark_outline_rounded;
  }
}

class _SubcategoryTile extends StatelessWidget {
  const _SubcategoryTile({
    required this.state,
    required this.linha,
    required this.color,
  });

  final AppState state;
  final BudgetLine linha;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    String valor(double v) =>
        state.hideBalances ? '••••' : state.formatValue(v, 'BRL', signed: false);

    return InkWell(
      onTap: () => showBudgetGoalDialog(context, state: state, node: linha.node),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    linha.node.name,
                    style: context.texts.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  valor(linha.spent),
                  style: context.texts.bodyMedium?.copyWith(
                    color: linha.exceeded ? tones.negative : null,
                  ),
                ),
                _MenuDaSubcategoria(state: state, node: linha.node),
              ],
            ),
            if (linha.hasBudget) ...[
              const SizedBox(height: 4),
              Padding(
                // Mesma leitura da categoria acima: meta sob o nome, saldo
                // sob o valor, e a barra ocupando a largura toda.
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Meta: ${valor(linha.budget)}',
                            style: context.texts.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          linha.exceeded
                              ? 'Excedeu: ${valor(linha.remaining.abs())}'
                              : 'Resta: ${valor(linha.remaining)}',
                          style: context.texts.bodySmall?.copyWith(
                            color: linha.exceeded ? tones.negative : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: linha.progress,
                        minHeight: 4,
                        backgroundColor: tones.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation(
                          linha.exceeded ? tones.negative : color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ações de uma subcategoria: meta, renomear e apagar.
class _MenuDaSubcategoria extends StatelessWidget {
  const _MenuDaSubcategoria({required this.state, required this.node});

  final AppState state;
  final BudgetNode node;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Opções',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded, size: 18, color: context.tones.muted),
      onSelected: (acao) async {
        switch (acao) {
          case 'meta':
            await showBudgetGoalDialog(context, state: state, node: node);
          case 'renomear':
            if (context.mounted) await _renomear(context);
          case 'apagar':
            if (context.mounted) await _apagar(context);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'meta', child: Text('Definir meta')),
        PopupMenuItem(value: 'renomear', child: Text('Renomear')),
        PopupMenuItem(value: 'apagar', child: Text('Apagar')),
      ],
    );
  }

  Future<void> _renomear(BuildContext context) async {
    final controller = TextEditingController(text: node.name);
    final novo = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Renomear'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (t) => Navigator.of(d).pop(t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (novo != null) await state.renameBudgetNode(node.id, novo);
  }

  Future<void> _apagar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Apagar "${node.name}"?'),
        content: Text(
          node.sources.isEmpty
              ? 'A subcategoria some do planejamento.'
              : 'Os gastos dela passam a contar direto na categoria acima — '
                  'nada some do planejamento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok == true) await state.removeBudgetNode(node.id);
  }
}

/// Caixa para definir a meta mensal de uma categoria.
Future<void> showBudgetGoalDialog(
  BuildContext context, {
  required AppState state,
  required BudgetNode node,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BudgetGoalDialog(state: state, node: node),
  );
}

class _BudgetGoalDialog extends StatefulWidget {
  const _BudgetGoalDialog({required this.state, required this.node});

  final AppState state;
  final BudgetNode node;

  @override
  State<_BudgetGoalDialog> createState() => _BudgetGoalDialogState();
}

class _BudgetGoalDialogState extends State<_BudgetGoalDialog> {
  late final TextEditingController _controller = TextEditingController(
    // A meta é guardada em reais, mas editada na moeda que está na tela.
    text: widget.node.budget > 0
        ? widget.state
            .brlToDisplay(widget.node.budget)
            .toStringAsFixed(2)
            .replaceAll('.', ',')
        : '',
  );

  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final digitado =
        double.tryParse(_controller.text.replaceAll(',', '.')) ?? 0;

    final recusa = await widget.state
        .setBudget(widget.node.id, widget.state.displayToBrl(digitado));

    if (!mounted) return;
    if (recusa != null) {
      setState(() => _erro = recusa);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cabe = state.budgetHeadroomFor(widget.node.id);

    return AlertDialog(
      title: Text('Meta de ${widget.node.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quanto você pretende gastar por mês nesta categoria. Deixe vazio '
            'para remover a meta.',
            style: context.texts.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: state.displayCurrencySymbol,
              labelText: 'Meta mensal',
              // Deixa claro o teto antes de o usuário esbarrar nele.
              helperText: cabe == null
                  ? null
                  : 'Cabem até ${fmtFiat(state.brlToDisplay(cabe), brl: state.showInBrl)}',
              helperMaxLines: 2,
            ),
            onSubmitted: (_) => _salvar(),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 14),
            ErrorBanner(message: _erro!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}

/// Folha para criar uma categoria ou subcategoria.
Future<void> showBudgetNodeEditor(
  BuildContext context, {
  required AppState state,
  String? parentId,
  String? parentName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _NodeEditor(
      state: state,
      parentId: parentId,
      parentName: parentName,
    ),
  );
}

class _NodeEditor extends StatefulWidget {
  const _NodeEditor({required this.state, this.parentId, this.parentName});

  final AppState state;
  final String? parentId;
  final String? parentName;

  @override
  State<_NodeEditor> createState() => _NodeEditorState();
}

class _NodeEditorState extends State<_NodeEditor> {
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController();
  final Set<String> _sources = {};

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nameController.text.trim();
    if (nome.isEmpty) return;

    final digitado =
        double.tryParse(_budgetController.text.replaceAll(',', '.')) ?? 0;

    await widget.state.addBudgetNode(
      name: nome,
      parentId: widget.parentId,
      // A meta entra na moeda da tela e é guardada em reais.
      budget: widget.state.displayToBrl(digitado),
      sources: _sources.toList(),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final ehSub = widget.parentId != null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              children: [
                Text(
                  ehSub ? 'Nova subcategoria' : 'Nova categoria',
                  style: context.texts.headlineSmall,
                ),
                if (ehSub) ...[
                  const SizedBox(height: 6),
                  Text('Dentro de ${widget.parentName}',
                      style: context.texts.bodySmall),
                ],
                const SizedBox(height: 22),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    hintText: 'Ex.: Academia, Pets, Viagens',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _budgetController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Meta mensal (opcional)',
                    prefixText: widget.state.displayCurrencySymbol,
                  ),
                ),
                const SizedBox(height: 24),
                Text('Que gastos entram aqui', style: context.texts.titleSmall),
                const SizedBox(height: 6),
                Text(
                  'Escolha as categorias de gasto que devem alimentar esta '
                  'categoria. Cada uma pertence a um lugar só, então ela sai '
                  'de onde estava hoje.',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final categoria in SpendCategories.all)
                      FilterChip(
                        label: Text(categoria),
                        selected: _sources.contains(categoria),
                        showCheckmark: false,
                        avatar: Icon(
                          categoryIcon(categoria),
                          size: 16,
                          color: _sources.contains(categoria)
                              ? AppColors.accent
                              : context.tones.muted,
                        ),
                        onSelected: (marcada) => setState(() {
                          if (marcada) {
                            _sources.add(categoria);
                          } else {
                            _sources.remove(categoria);
                          }
                        }),
                        backgroundColor: context.tones.surfaceAlt,
                        selectedColor: AppColors.accent.withValues(alpha: 0.14),
                        side: BorderSide(
                          color: _sources.contains(categoria)
                              ? AppColors.accent
                              : context.tones.border,
                        ),
                        labelStyle: context.texts.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _salvar,
                  child: const Text('Criar'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
