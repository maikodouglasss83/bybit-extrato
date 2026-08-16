import 'package:flutter/material.dart';

import '../../app_state.dart';
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
    );
    await widget.state.setFixed(widget.entry, _fixo);
    // O dia só faz sentido em compromisso mensal.
    await widget.state.setDueDay(widget.entry, _fixo ? _diaVencimento : null);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _reset() async {
    await widget.state.clearOverridesFor(widget.entry);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.state.originalNameOf(widget.entry);
    final ajustado = widget.state.hasCustomizations(widget.entry);

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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Inclui as categorias criadas no planejamento.
                    for (final categoria in widget.state.availableCategories)
                      _CategoryChip(
                        label: categoria,
                        selected: categoria == _category,
                        custom: widget.state.isCustomCategory(categoria),
                        onTap: () => setState(() => _category = categoria),
                      ),
                  ],
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
                  if (ajustado) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _reset,
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        label: const Text('Restaurar nome e categoria originais'),
                      ),
                    ),
                  ],
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.custom = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Criada pelo usuário no planejamento, e não uma das que o app reconhece.
  final bool custom;

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
            Icon(
              custom ? Icons.bookmark_outline_rounded : categoryIcon(label),
              size: 16,
              color: cor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: context.texts.bodySmall?.copyWith(
                color: selected ? context.colors.onSurface : context.tones.muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
