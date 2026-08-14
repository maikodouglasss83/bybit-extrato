import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';
import '../../util/categorizer.dart';

/// Ícone que representa cada categoria de gasto.
IconData categoryIcon(String category) {
  switch (category) {
    case SpendCategories.assinaturas:
      return Icons.subscriptions_outlined;
    case SpendCategories.telefonia:
      return Icons.wifi_rounded;
    case SpendCategories.transporte:
      return Icons.directions_car_filled_outlined;
    case SpendCategories.mercado:
      return Icons.shopping_cart_outlined;
    case SpendCategories.restaurantes:
      return Icons.restaurant_rounded;
    case SpendCategories.compras:
      return Icons.shopping_bag_outlined;
    case SpendCategories.tecnologia:
      return Icons.memory_rounded;
    case SpendCategories.saude:
      return Icons.favorite_border_rounded;
    case SpendCategories.educacao:
      return Icons.school_outlined;
    case SpendCategories.lazer:
      return Icons.sports_esports_outlined;
    case SpendCategories.vestuario:
      return Icons.checkroom_rounded;
    case SpendCategories.casa:
      return Icons.home_outlined;
    case SpendCategories.servicos:
      return Icons.handyman_outlined;
    case SpendCategories.transferencias:
      return Icons.swap_horiz_rounded;
    default:
      return Icons.more_horiz_rounded;
  }
}

/// Cartão padrão do app.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

/// Rótulo pequeno em caixa alta usado acima das seções.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(), style: context.texts.labelSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Ícone circular que representa o tipo de movimentação.
class KindAvatar extends StatelessWidget {
  const KindAvatar({
    super.key,
    required this.kind,
    required this.isIn,
    this.size = 42,
    this.overrideIcon,
  });

  final LedgerKind kind;
  final bool isIn;
  final double size;

  /// Substitui o ícone padrão do tipo, usado para mostrar o ramo da compra.
  final IconData? overrideIcon;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final color = switch (kind) {
      LedgerKind.deposit || LedgerKind.transferIn => tones.positive,
      LedgerKind.withdraw || LedgerKind.transferOut => tones.negative,
      LedgerKind.internalTransfer => AppColors.accent,
      LedgerKind.cardPurchase => tones.negative,
      LedgerKind.cardRefund => tones.positive,
      LedgerKind.trade => AppColors.accent,
      LedgerKind.funding || LedgerKind.interest => AppColors.warning,
      LedgerKind.fee => tones.muted,
      LedgerKind.bonus => AppColors.accent,
      LedgerKind.settlement => AppColors.warning,
      LedgerKind.other => isIn ? tones.positive : tones.muted,
    };

    final icon = switch (kind) {
      LedgerKind.deposit => Icons.south_west_rounded,
      LedgerKind.withdraw => Icons.north_east_rounded,
      LedgerKind.transferIn => Icons.call_received_rounded,
      LedgerKind.transferOut => Icons.call_made_rounded,
      LedgerKind.internalTransfer => Icons.swap_vert_rounded,
      LedgerKind.cardPurchase => Icons.credit_card_rounded,
      LedgerKind.cardRefund => Icons.replay_rounded,
      LedgerKind.trade => Icons.swap_horiz_rounded,
      LedgerKind.funding => Icons.autorenew_rounded,
      LedgerKind.fee => Icons.receipt_long_rounded,
      LedgerKind.interest => Icons.percent_rounded,
      LedgerKind.bonus => Icons.card_giftcard_rounded,
      LedgerKind.settlement => Icons.gavel_rounded,
      LedgerKind.other => Icons.circle_outlined,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(overrideIcon ?? icon, color: color, size: size * 0.5),
    );
  }
}

/// Sigla da moeda em um círculo, com cor derivada do próprio nome.
class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.coin, this.size = 40});

  final String coin;
  final double size;

  static const _palette = [
    Color(0xFFF7931A), // laranja
    Color(0xFF627EEA), // azul
    Color(0xFF22D3A6), // verde-água
    Color(0xFFF4436B), // rosa
    Color(0xFFA78BFA), // roxo
    Color(0xFF38BDF8), // ciano
    Color(0xFFF5A524), // âmbar
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[coin.hashCode.abs() % _palette.length];
    final label = coin.length <= 4 ? coin : coin.substring(0, 4);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: label.length >= 4 ? size * 0.26 : size * 0.32,
        ),
      ),
    );
  }
}

/// Estado vazio com ícone, título e explicação.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.tones.surfaceAlt,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 30, color: context.tones.muted),
              ),
              const SizedBox(height: 18),
              Text(title, style: context.texts.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: context.texts.bodySmall, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa de erro discreta, com opção de tentar de novo.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: tones.negative.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tones.negative.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: tones.negative, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: context.texts.bodySmall)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }
}

/// Substitui o valor por pontos quando o usuário esconde os saldos.
class MaskedValue extends StatelessWidget {
  const MaskedValue({
    super.key,
    required this.value,
    required this.hidden,
    required this.style,
    this.maskLength = 6,
  });

  final String value;
  final bool hidden;
  final TextStyle? style;
  final int maskLength;

  @override
  Widget build(BuildContext context) {
    return Text(hidden ? '•' * maskLength : value, style: style);
  }
}
