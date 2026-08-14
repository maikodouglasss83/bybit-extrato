import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../util/brands.dart';
import 'common.dart';

/// Selo do estabelecimento numa compra do cartão.
///
/// A ordem é: logo baixado (só se o usuário permitir), monograma na cor da
/// marca, e por fim o ícone da categoria. Assim a lista fica reconhecível de
/// relance mesmo sem nenhuma requisição à internet.
class MerchantAvatar extends StatelessWidget {
  const MerchantAvatar({
    super.key,
    required this.entry,
    required this.state,
    this.size = 42,
  });

  final LedgerEntry entry;
  final AppState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = brandFor(entry.note);

    // Sem marca conhecida, o ícone da categoria já diz do que se trata.
    if (brand == null) {
      return KindAvatar(
        kind: entry.kind,
        isIn: entry.isIn,
        size: size,
        overrideIcon: entry.kind == LedgerKind.cardPurchase
            ? categoryIcon(state.categoryOf(entry))
            : null,
      );
    }

    final radius = BorderRadius.circular(size / 3);
    final monograma = _Monogram(brand: brand, size: size, radius: radius);

    if (!state.useOnlineLogos || brand.domain == null) return monograma;

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        'https://favicone.com/${brand.domain}?s=128',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Enquanto baixa, e se falhar, o monograma segura o lugar sem piscar.
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : monograma,
        errorBuilder: (_, __, ___) => monograma,
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.brand, required this.size, required this.radius});

  final Brand brand;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.color.withValues(alpha: 0.16),
        borderRadius: radius,
        border: Border.all(color: brand.color.withValues(alpha: 0.35)),
      ),
      child: Text(
        brand.label,
        style: TextStyle(
          color: brand.color,
          fontWeight: FontWeight.w800,
          fontSize: brand.label.length >= 2 ? size * 0.34 : size * 0.44,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
