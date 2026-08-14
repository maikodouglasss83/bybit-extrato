import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'common.dart';
import 'entry_editor.dart';
import 'merchant_avatar.dart';

/// Botão para tirar um lançamento das contas, ou trazer de volta.
class _HideAction extends StatelessWidget {
  const _HideAction({required this.entry, required this.state});

  final LedgerEntry entry;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final oculto = state.isHidden(entry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await state.setHidden(entry, !oculto);
              if (context.mounted && !oculto) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Gasto ocultado e fora dos totais.'),
                  ),
                );
              }
            },
            icon: Icon(
              oculto ? Icons.visibility_rounded : Icons.visibility_off_outlined,
              size: 18,
            ),
            label: Text(oculto ? 'Voltar a considerar' : 'Ocultar este gasto'),
            style: OutlinedButton.styleFrom(
              foregroundColor: oculto ? AppColors.accent : context.tones.negative,
              side: BorderSide(
                color: (oculto ? AppColors.accent : context.tones.negative)
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          oculto
              ? 'Este lançamento está fora dos gráficos e dos totais.'
              : 'Some das listas e para de contar nos gráficos e totais. '
                  'Útil para transferências e reembolsos que não são gasto.',
          style: context.texts.bodySmall,
        ),
      ],
    );
  }
}

/// Uma linha do extrato.
class LedgerTile extends StatelessWidget {
  const LedgerTile({
    super.key,
    required this.entry,
    required this.state,
    this.onLongPress,
  });

  final LedgerEntry entry;
  final AppState state;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final valueColor = entry.neutral || entry.change == 0
        ? tones.muted
        : (entry.isIn ? tones.positive : tones.negative);

    final usd = state.usdValueOf(entry.coin, entry.change.abs());
    // Só vale mostrar a conversão embaixo quando o valor de cima ainda está
    // na moeda original.
    final fiat = usd > 0 && !state.showsConverted(entry.coin)
        ? fmtFiat(state.toDisplay(usd), brl: state.showInBrl)
        : null;

    // Numa compra o que importa é o estabelecimento; o tipo vira detalhe.
    final title = entry.isCard && entry.note != null
        ? state.displayNameOf(entry)
        : kindLabel(entry.kind, entry.rawType);
    final subtitle = [
      fmtTime(entry.time),
      if (entry.isCard) state.categoryOf(entry),
      if (!entry.isCard && entry.note != null) entry.note!,
      if (entry.symbol != null) entry.symbol!,
      if (entry.status != null) entry.status!,
    ].join(' · ');

    final oculto = state.isHidden(entry);

    return InkWell(
      onTap: () => _showDetails(context),
      onLongPress: onLongPress ??
          (entry.isCard
              ? () => showEntryEditor(context, state: state, entry: entry)
              : null),
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        // O oculto continua na lista, riscado e apagado, para dar para
        // conferir e desfazer sem se confundir com o que está sendo contado.
        opacity: oculto ? 0.5 : 1,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            MerchantAvatar(entry: entry, state: state),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (oculto) ...[
                        Icon(Icons.visibility_off_rounded,
                            size: 14, color: context.tones.muted),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          title,
                          style: context.texts.titleSmall?.copyWith(
                            decoration: oculto ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    oculto ? '$subtitle · fora dos totais' : subtitle,
                    style: context.texts.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MaskedValue(
                  hidden: state.hideBalances,
                  maskLength: 5,
                  value: state.formatValue(entry.change, entry.coin,
                      signed: !entry.neutral),
                  style: context.texts.titleSmall?.copyWith(
                    color: oculto ? context.tones.muted : valueColor,
                    decoration: oculto ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (entry.points != null && entry.points! > 0) ...[
                  const SizedBox(height: 3),
                  Text('${entry.points} pts', style: context.texts.bodySmall),
                ] else if (fiat != null && entry.coin.toUpperCase() != 'BRL') ...[
                  const SizedBox(height: 3),
                  MaskedValue(
                    hidden: state.hideBalances,
                    maskLength: 4,
                    value: fiat,
                    style: context.texts.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Folhas modais vivem fora da árvore que escuta o estado, então
      // precisam observar o AppState para refletir renomeações na hora.
      builder: (sheetContext) => AnimatedBuilder(
        animation: state,
        builder: (_, __) => _LedgerDetails(entry: entry, state: state),
      ),
    );
  }
}

class _LedgerDetails extends StatelessWidget {
  const _LedgerDetails({required this.entry, required this.state});

  final LedgerEntry entry;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final valueColor = entry.neutral
        ? context.colors.onSurface
        : (entry.isIn ? tones.positive : tones.negative);
    final usd = state.usdValueOf(entry.coin, entry.change.abs());

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MerchantAvatar(entry: entry, state: state, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.isCard && entry.note != null
                            ? state.displayNameOf(entry)
                            : kindLabel(entry.kind, entry.rawType),
                        style: context.texts.headlineSmall,
                      ),
                      Text(fmtFullDate(entry.time), style: context.texts.bodySmall),
                    ],
                  ),
                ),
                if (entry.isCard)
                  IconButton(
                    tooltip: 'Editar nome e categoria',
                    onPressed: () =>
                        showEntryEditor(context, state: state, entry: entry),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              state.formatValue(entry.change, entry.coin, signed: !entry.neutral),
              style: context.texts.displaySmall?.copyWith(color: valueColor),
            ),
            // Com o valor já convertido em cima, mostra o original embaixo
            // para dar para conferir contra a fatura.
            if (state.showsConverted(entry.coin) && entry.coin.toUpperCase() != 'USD')
              Text(
                'Na fatura: ${fmtAmount(entry.change.abs(), entry.coin, signed: false)}',
                style: context.texts.bodySmall,
              )
            else if (usd > 0)
              Text(
                '≈ ${fmtFiat(state.toDisplay(usd), brl: state.showInBrl)}',
                style: context.texts.bodySmall,
              ),
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 8),
            _row(context, 'Moeda', entry.coin),
            // Com apelido, o nome da fatura vira informação de conferência.
            if (entry.isCard && entry.note != null)
              _row(
                context,
                state.hasCustomName(entry) ? 'Nome na fatura' : 'Estabelecimento',
                entry.note!,
              )
            else if (entry.note != null)
              _row(context, 'Caminho', entry.note!),
            if (entry.isCard) _categoryRow(context),
            if (entry.cardLast4 != null) _row(context, 'Cartão', '•••• ${entry.cardLast4}'),
            if (entry.points != null && entry.points! > 0)
              _row(context, 'Pontos ganhos', '${entry.points}'),
            if (entry.symbol != null) _row(context, 'Par', entry.symbol!),
            if (entry.side != null) _row(context, 'Lado', entry.side!),
            if (entry.fee != 0) _row(context, 'Taxa', '${fmtCrypto(entry.fee)} ${entry.coin}'),
            if (entry.balanceAfter != null)
              _row(context, 'Saldo após', '${fmtCrypto(entry.balanceAfter!)} ${entry.coin}'),
            if (entry.status != null) _row(context, 'Situação', entry.status!),
            if (entry.txId != null && entry.txId!.isNotEmpty)
              _row(context, 'Transação', entry.txId!, mono: true),
            _row(context, 'Origem', _sourceLabelOf(entry.source)),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 12),
            _HideAction(entry: entry, state: state),
          ],
        ),
      ),
    );
  }

  static String _sourceLabelOf(String source) => switch (source) {
        'deposit' => 'Registro de depósitos',
        'withdraw' => 'Registro de saques',
        'transfer' => 'Transferências internas',
        'card' => 'Bybit Card',
        _ => 'Extrato da conta',
      };

  /// Linha da categoria, com atalho para corrigi-la.
  Widget _categoryRow(BuildContext context) {
    final categoria = state.categoryOf(entry);
    final ajustada = state.hasCustomCategory(entry);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text('Categoria', style: context.texts.bodySmall),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(categoryIcon(categoria), size: 17, color: AppColors.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    categoria,
                    style: context.texts.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ajustada) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Categoria ajustada por você',
                    child: Icon(Icons.push_pin_rounded,
                        size: 13, color: context.tones.muted),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => showEntryEditor(context, state: state, entry: entry),
            child: const Text('Alterar'),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: context.texts.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono
                  ? context.texts.bodySmall?.copyWith(fontFamily: 'monospace')
                  : context.texts.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
