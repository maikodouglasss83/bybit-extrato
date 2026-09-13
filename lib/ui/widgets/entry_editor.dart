import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../budget.dart';
import '../../models.dart';
import '../../theme.dart';
import 'common.dart';

/// Folha para renomear um estabelecimento e ajustar a categoria dele.
///
/// As duas mudanças valem para todas as compras do mesmo lugar, inclusive as
/// futuras — é o que se espera de quem corrige uma classificação errada.
Future<void> showEntryEditor(
  BuildContext context, {
  required AppState state,
  required LedgerEntry entry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _EntryEditor(state: state, entry: entry),
  );
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.state, required this.entry});

  final AppState state;
  final LedgerEntry entry;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.state.displayNameOf(widget.entry));
  final FocusNode _nameFocus = FocusNode();
  late String _category = widget.state.categoryOf(widget.entry);
  late bool _fixo = widget.state.isFixed(widget.entry);
  late int? _diaVencimento = widget.state.dueDayOf(widget.entry);

  /// Onde o novo nome vale. O padrão é só nesta compra: duas compras no mesmo
  /// lugar costumam ser coisas diferentes, e mexer nas duas de uma vez é a
  /// exceção — que fica a um toque de distância.
  late bool _soEstaCompra =
      widget.state.hasEntryName(widget.entry) ||
          !widget.state.hasCustomName(widget.entry);

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Limpar sem devolver o foco obriga o usuário a tocar no campo de novo.
  void _clearName() {
    _nameController.clear();
    _nameFocus.requestFocus();
  }

  Future<void> _save() async {
    await widget.state.setEntryOverrides(
      widget.entry,
      name: _nameController.text,
      category: _category,
      nameOnlyThis: _soEstaCompra,
    );
    await widget.state.setFixed(widget.entry, _fixo);
    // O dia só faz sentido em compromisso mensal.
    await widget.state.setDueDay(widget.entry, _fixo ? _diaVencimento : null);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.state.originalNameOf(widget.entry);
    final irmas = widget.state.merchantEntryCount(widget.entry);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              children: [
                Text('Editar', style: context.texts.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  'Vale para todas as compras neste estabelecimento, '
                  'inclusive as próximas.',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 22),
                Text('Nome', style: context.texts.titleSmall),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: original ?? 'Nome do estabelecimento',
                    prefixIcon: Icon(categoryIcon(_category), size: 20),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _nameController,
                      builder: (_, value, __) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'Limpar',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: _clearName,
                            ),
                    ),
                  ),
                ),
                if (original != null && original.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.receipt_rounded,
                          size: 13, color: context.tones.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Na fatura: $original',
                          style: context.texts.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (irmas > 1) ...[
                  const SizedBox(height: 22),
                  Text('Este nome vale para', style: context.texts.titleSmall),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Opcao(
                          selecionada: _soEstaCompra,
                          icone: Icons.receipt_long_rounded,
                          titulo: 'Só esta compra',
                          descricao: 'As outras não mudam',
                          onTap: () => setState(() => _soEstaCompra = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Opcao(
                          selecionada: !_soEstaCompra,
                          icone: Icons.storefront_rounded,
                          titulo: 'O lugar todo',
                          descricao: '$irmas compras aqui',
                          onTap: () => setState(() => _soEstaCompra = false),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 26),
                Text('Tipo de gasto', style: context.texts.titleSmall),
                const SizedBox(height: 10),
                _TipoDeGasto(
                  fixo: _fixo,
                  onChanged: (v) => setState(() => _fixo = v),
                ),
                if (_fixo) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    initialValue: _diaVencimento,
                    decoration: const InputDecoration(
                      labelText: 'Vence no dia',
                      prefixIcon: Icon(Icons.event_rounded, size: 20),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Deduzir do histórico'),
                      ),
                      for (var dia = 1; dia <= 31; dia++)
                        DropdownMenuItem<int?>(
                          value: dia,
                          child: Text('Dia $dia'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _diaVencimento = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _diaVencimento == null
                        ? 'Sem definir, o app usa o dia em que este gasto '
                            'costuma cair.'
                        : 'Meses mais curtos usam o último dia — o 31 vira 28 '
                            'em fevereiro.',
                    style: context.texts.bodySmall,
                  ),
                ],
                const SizedBox(height: 26),
                Text('Categoria', style: context.texts.titleSmall),
                const SizedBox(height: 12),
                _SeletorDeCategoria(
                  state: widget.state,
                  selecionada: _category,
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Salvar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      // Fecha sem salvar e volta para a tela de onde veio.
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escolha entre compromisso mensal e gasto do dia a dia.
class _TipoDeGasto extends StatelessWidget {
  const _TipoDeGasto({required this.fixo, required this.onChanged});

  final bool fixo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Opcao(
            selecionada: fixo,
            icone: Icons.event_repeat_rounded,
            titulo: 'Fixo',
            descricao: 'Chega todo mês',
            onTap: () => onChanged(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Opcao(
            selecionada: !fixo,
            icone: Icons.shopping_bag_outlined,
            titulo: 'Variável',
            descricao: 'Depende do mês',
            onTap: () => onChanged(false),
          ),
        ),
      ],
    );
  }
}

class _Opcao extends StatelessWidget {
  const _Opcao({
    required this.selecionada,
    required this.icone,
    required this.titulo,
    required this.descricao,
    required this.onTap,
  });

  final bool selecionada;
  final IconData icone;
  final String titulo;
  final String descricao;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cor = selecionada ? AppColors.accent : context.tones.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selecionada
              ? AppColors.accent.withValues(alpha: 0.12)
              : context.tones.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selecionada ? AppColors.accent : context.tones.border,
            width: selecionada ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 20, color: cor),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: context.texts.titleSmall?.copyWith(
                color: selecionada ? context.colors.onSurface : context.tones.muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(descricao, style: context.texts.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Escolha da categoria em dois níveis: primeiro a principal, depois a
/// subcategoria. Acompanha a estrutura montada no planejamento, em vez de
/// jogar dezenas de opções soltas na tela.
class _SeletorDeCategoria extends StatefulWidget {
  const _SeletorDeCategoria({
    required this.state,
    required this.selecionada,
    required this.onChanged,
  });

  final AppState state;
  final String selecionada;
  final ValueChanged<String> onChanged;

  @override
  State<_SeletorDeCategoria> createState() => _SeletorDeCategoriaState();
}

class _SeletorDeCategoriaState extends State<_SeletorDeCategoria> {
  BudgetNode? _principal;

  @override
  void initState() {
    super.initState();
    // Abre já na principal da categoria atual, para o usuário ver onde está.
    _principal = widget.state.mainCategoryOf(widget.selecionada);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final principais = state.selectableMainCategories;
    final aberta = _principal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final main in principais)
              _CategoryChip(
                label: main.name,
                icon: _iconeDe(state, main),
                selected: aberta?.id == main.id,
                // A principal que contém a escolha atual fica marcada mesmo
                // quando o usuário está navegando em outra.
                trailing: state.mainCategoryOf(widget.selecionada)?.id == main.id
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                onTap: () => setState(() {
                  _principal = aberta?.id == main.id ? null : main;
                }),
              ),
            _AdicionarChip(
              label: 'Nova categoria',
              onTap: () => _criar(context),
            ),
          ],
        ),
        if (aberta != null) ...[
          const SizedBox(height: 16),
          Text(
            'Subcategorias',
            style: context.texts.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sub in state.subcategoriesFor(aberta))
                _CategoryChip(
                  label: sub.name,
                  icon: _iconeDe(state, sub),
                  selected: state.categoryValueOf(sub) == widget.selecionada,
                  onTap: () =>
                      widget.onChanged(state.categoryValueOf(sub)),
                ),
              _AdicionarChip(
                label: 'Nova subcategoria',
                onTap: () => _criar(context, parent: aberta),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Cria a categoria ali mesmo, sem sair da compra, e já a deixa escolhida.
  ///
  /// Quem cria uma categoria no meio de uma edição quer usá-la nesta compra;
  /// fazer a pessoa procurar o que acabou de criar seria trabalho à toa. A
  /// escolha só vale depois de salvar, como qualquer outra.
  Future<void> _criar(BuildContext context, {BudgetNode? parent}) async {
    final state = widget.state;
    final nome = await showDialog<String>(
      context: context,
      builder: (_) => _NovaCategoriaDialog(
        titulo: parent == null ? 'Nova categoria' : 'Nova subcategoria',
        dentroDe: parent?.name,
        criar: (nome) => state.addBudgetNode(name: nome, parentId: parent?.id),
      ),
    );
    if (nome == null || !mounted) return;

    final criado = state.budgetNodes.where((n) => n.name == nome).lastOrNull;
    if (criado == null) return;

    setState(() => _principal = parent ?? criado);
    widget.onChanged(state.categoryValueOf(criado));
  }

  /// O mesmo ícone que a categoria tem no planejamento.
  static IconData _iconeDe(AppState state, BudgetNode node) {
    if (node.isMain) return mainCategoryIcon(node.id);
    if (node.sources.isEmpty) return iconForCategoryName(node.name);
    final valor = node.sources.first;
    return state.isCustomCategory(valor)
        ? iconForCategoryName(node.name)
        : categoryIcon(valor);
  }
}

/// Chip de criar, no fim de cada lista: parece com as opções, mas traz o "+"
/// e a cor de ação, para não ser confundido com uma categoria.
class _AdicionarChip extends StatelessWidget {
  const _AdicionarChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.texts.bodySmall?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pede o nome de uma categoria nova e mostra ali mesmo por que não deu.
class _NovaCategoriaDialog extends StatefulWidget {
  const _NovaCategoriaDialog({
    required this.titulo,
    required this.criar,
    this.dentroDe,
  });

  final String titulo;

  /// Principal onde a subcategoria vai entrar; nulo para uma principal.
  final String? dentroDe;

  /// Cria de fato. Devolve o motivo quando não dá, ou nulo quando criou.
  final Future<String?> Function(String nome) criar;

  @override
  State<_NovaCategoriaDialog> createState() => _NovaCategoriaDialogState();
}

class _NovaCategoriaDialogState extends State<_NovaCategoriaDialog> {
  final _nome = TextEditingController();
  String? _erro;
  bool _criando = false;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      setState(() => _erro = 'Dê um nome para a categoria.');
      return;
    }

    setState(() {
      _criando = true;
      _erro = null;
    });
    final erro = await widget.criar(nome);
    if (!mounted) return;

    if (erro != null) {
      setState(() {
        _criando = false;
        _erro = erro;
      });
      return;
    }
    Navigator.of(context).pop(nome);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.dentroDe != null) ...[
            Text('Dentro de ${widget.dentroDe}', style: context.texts.bodySmall),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nome,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _confirmar(),
            onChanged: (_) {
              if (_erro != null) setState(() => _erro = null);
            },
            decoration: InputDecoration(labelText: 'Nome', errorText: _erro),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _criando ? null : _confirmar,
          child: const Text('Criar'),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.icon,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  /// Ícone à direita, usado para indicar que a principal tem conteúdo dentro.
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final cor = selected ? AppColors.accent : context.tones.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : context.tones.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : context.tones.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cor),
            const SizedBox(width: 8),
            Text(
              label,
              style: context.texts.bodySmall?.copyWith(
                color: selected ? context.colors.onSurface : context.tones.muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              Icon(
                trailing,
                size: 14,
                color: trailing == Icons.check_circle_rounded
                    ? AppColors.accent
                    : context.tones.muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
