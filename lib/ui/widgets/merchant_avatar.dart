import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../util/brands.dart';
import 'common.dart';

/// Selo de um lançamento: o ícone da categoria dele, na cor dela.
///
/// É o mesmo desenho do planejamento, então a lista se lê pelo tipo de gasto —
/// mercado, transporte, streaming — em vez de uma coluna de iniciais que não
/// dizem nada. O logo da marca só entra quando o usuário liga os logos
/// baixados; enquanto carrega, ou se falhar, o selo da categoria fica no lugar.
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
    // Depósito, saque e transferência não têm categoria: o desenho é o do tipo.
    if (entry.kind != LedgerKind.cardPurchase) {
      return KindAvatar(kind: entry.kind, isIn: entry.isIn, size: size);
    }

    return BrandAvatar(
      name: entry.note ?? '',
      state: state,
      category: state.categoryOf(entry),
      size: size,
    );
  }
}

/// Logo da marca, quando os logos baixados estão ligados e a marca é
/// conhecida; senão, o selo da categoria.
class BrandAvatar extends StatelessWidget {
  const BrandAvatar({
    super.key,
    required this.name,
    required this.state,
    required this.category,
    this.size = 42,
  });

  final String name;
  final AppState state;

  /// Categoria de gasto que dá o ícone e a cor do selo.
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final selo = CategoryBadge(state: state, category: category, size: size);

    final dominio = brandFor(name)?.domain;
    if (!state.useOnlineLogos || dominio == null) return selo;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 3),
      child: Image.network(
        'https://favicone.com/$dominio?s=128',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Enquanto baixa, e se falhar, o selo segura o lugar sem piscar.
        loadingBuilder: (_, child, progress) => progress == null ? child : selo,
        errorBuilder: (_, __, ___) => selo,
      ),
    );
  }
}

/// Quadrado arredondado com o ícone da categoria, na cor da principal.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({
    super.key,
    required this.state,
    required this.category,
    this.size = 42,
  });

  final AppState state;
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icone, cor) = categoryVisual(state, category, context.tones.muted);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(icone, size: size * 0.48, color: cor),
    );
  }
}

/// Ícone e cor de uma categoria de gasto, como no planejamento.
///
/// O ícone é o da subcategoria que recebe a compra; a cor, a da categoria
/// principal acima dela. Categoria fora do planejamento — a de uma assinatura
/// cadastrada à mão, por exemplo — ganha o ícone pelo nome e uma cor fixa.
(IconData, Color) categoryVisual(
  AppState state,
  String category,
  Color semCategoria,
) {
  if (category.trim().isEmpty) return (Icons.autorenew_rounded, semCategoria);

  final no = state.nodeForCategory(category);
  final principal = state.mainCategoryOf(category);

  final icone = no != null ? iconForBudgetNode(no) : categoryIcon(category);
  final cor = principal != null
      ? mainCategoryColor(principal.id)
      : colorForMerchant(category);
  return (icone, cor);
}

/// Cor fixa para um nome sem categoria principal conhecida.
///
/// Sai do próprio nome: a mesma categoria tem sempre a mesma cor.
Color colorForMerchant(String chave) {
  const paleta = [
    Color(0xFF22D3A6),
    Color(0xFF6C8CFF),
    Color(0xFFF5A524),
    Color(0xFFA78BFA),
    Color(0xFF38BDF8),
    Color(0xFFF4436B),
    Color(0xFF2DD4BF),
    Color(0xFFFB923C),
    Color(0xFF818CF8),
    Color(0xFF4ADE80),
  ];
  if (chave.isEmpty) return paleta.first;
  return paleta[chave.hashCode.abs() % paleta.length];
}
