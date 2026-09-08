import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
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
    if (brand != null) {
      return _BrandBadge(
        brand: brand,
        size: size,
        useOnlineLogos: state.useOnlineLogos,
      );
    }

    // Numa compra, o que identifica a linha é o lugar onde ela aconteceu.
    // Sem marca conhecida, as iniciais do estabelecimento distinguem uma da
    // outra muito melhor do que o mesmo ícone repetido em todas.
    if (entry.kind == LedgerKind.cardPurchase) {
      final nome = state.displayNameOf(entry);
      final iniciais = initialsFor(nome);
      if (iniciais.isNotEmpty) {
        return _Monogram(
          label: iniciais,
          color: colorForMerchant(AppState.merchantKeyFor(entry.note)),
          size: size,
          radius: BorderRadius.circular(size / 3),
        );
      }
    }

    return KindAvatar(
      kind: entry.kind,
      isIn: entry.isIn,
      size: size,
      overrideIcon: entry.kind == LedgerKind.cardPurchase
          ? categoryIcon(state.categoryOf(entry))
          : null,
    );
  }
}

/// Iniciais de um estabelecimento, para o selo de quem não tem marca
/// conhecida: "Hashtag Treinamentos" vira HT, "Bumper" vira BU.
///
/// Os pedaços que a maquininha acrescenta — PAG, LTDA, a cidade, o número do
/// terminal — não identificam nada e ficam de fora.
String initialsFor(String nome) {
  const ruido = {
    'pag', 'pagto', 'pgto', 'pagamento', 'compra', 'cartao', 'cartão',
    'ltda', 'me', 'mei', 'eireli', 'sa', 'br', 'bra', 'com', 'www',
    'do', 'da', 'de', 'dos', 'das', 'e',
  };

  final limpo = nome.replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ');
  final palavras = limpo
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .where((p) => !ruido.contains(p.toLowerCase()))
      .where((p) => !RegExp(r'^\d+$').hasMatch(p))
      .toList();

  if (palavras.isEmpty) {
    final letra = nome.replaceAll(RegExp(r'\s'), '');
    return letra.isEmpty ? '' : letra.substring(0, 1).toUpperCase();
  }
  if (palavras.length == 1) {
    final unica = palavras.first;
    return (unica.length == 1 ? unica : unica.substring(0, 2)).toUpperCase();
  }
  return (palavras[0][0] + palavras[1][0]).toUpperCase();
}

/// Cor do selo de um estabelecimento sem marca conhecida.
///
/// Sai da chave do estabelecimento, e não do nome exibido: renomear a compra
/// não muda a cor com que você já se acostumou.
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

/// Selo de uma marca reconhecida pelo nome.
///
/// Serve para o que não tem uma compra por trás — uma assinatura cadastrada à
/// mão, por exemplo — e cai num ícone quando a marca é desconhecida.
class BrandAvatar extends StatelessWidget {
  const BrandAvatar({
    super.key,
    required this.name,
    required this.state,
    this.fallbackIcon = Icons.autorenew_rounded,
    this.size = 42,
  });

  final String name;
  final AppState state;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = brandFor(name);
    if (brand != null) {
      return _BrandBadge(
        brand: brand,
        size: size,
        useOnlineLogos: state.useOnlineLogos,
      );
    }

    final cor = context.tones.muted;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(fallbackIcon, size: size * 0.5, color: cor),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({
    required this.brand,
    required this.size,
    required this.useOnlineLogos,
  });

  final Brand brand;
  final double size;
  final bool useOnlineLogos;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size / 3);
    final monograma = _Monogram(
      label: brand.label,
      color: brand.color,
      size: size,
      radius: radius,
    );

    if (!useOnlineLogos || brand.domain == null) return monograma;

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

/// Selo com uma ou duas letras sobre a cor de quem ele representa.
class _Monogram extends StatelessWidget {
  const _Monogram({
    required this.label,
    required this.color,
    required this.size,
    required this.radius,
  });

  final String label;
  final Color color;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: radius,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: label.length >= 2 ? size * 0.34 : size * 0.44,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
