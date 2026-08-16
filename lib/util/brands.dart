import 'package:flutter/material.dart';

/// Identidade visual de um estabelecimento conhecido.
///
/// A cor não é sempre a oficial da marca: preto e amarelo puros somem no tema
/// escuro ou no claro, então cada uma foi ajustada para continuar legível nos
/// dois — mantendo o matiz que faz a marca ser reconhecida de relance.
class Brand {
  const Brand(this.label, this.color, {this.domain});

  /// Monograma exibido quando não há logo baixado.
  final String label;
  final Color color;

  /// Domínio usado para buscar o logo, quando o usuário liga essa opção.
  final String? domain;

  /// Identificador estável da marca.
  ///
  /// A Bybit manda o mesmo estabelecimento com grafias diferentes a cada mês
  /// — `DM*Spotify`, `DM *Spotify`, `NETFLIX.COM`, `NETFLIX ENTRETENIMENTO`.
  /// Este identificador é o que junta todas essas variações num só lugar,
  /// para apelidos, categorias e vencimentos valerem para a marca inteira.
  String get id => domain ?? '${label}_${color.toARGB32()}';
}

const _brands = <String, Brand>{
  // Streaming e assinaturas
  'netflix': Brand('N', Color(0xFFE50914), domain: 'netflix.com'),
  'spotify': Brand('S', Color(0xFF1DB954), domain: 'spotify.com'),
  'amazonprime': Brand('P', Color(0xFF00A8E1), domain: 'primevideo.com'),
  'prime video': Brand('P', Color(0xFF00A8E1), domain: 'primevideo.com'),
  'disney': Brand('D', Color(0xFF3B5BDB), domain: 'disneyplus.com'),
  'hbo': Brand('M', Color(0xFF9B4DEB), domain: 'max.com'),
  'globoplay': Brand('G', Color(0xFFE5372A), domain: 'globoplay.globo.com'),
  'youtube': Brand('Y', Color(0xFFFF0000), domain: 'youtube.com'),
  'crunchyroll': Brand('C', Color(0xFFF47521), domain: 'crunchyroll.com'),
  'deezer': Brand('D', Color(0xFFA238FF), domain: 'deezer.com'),
  'tinder': Brand('T', Color(0xFFFE3C72), domain: 'tinder.com'),
  'paramount': Brand('P', Color(0xFF0064FF), domain: 'paramountplus.com'),

  // Transporte
  'uber': Brand('U', Color(0xFF8A93A0), domain: 'uber.com'),
  '99app': Brand('99', Color(0xFFFFC800), domain: '99app.com'),
  '99pop': Brand('99', Color(0xFFFFC800), domain: '99app.com'),
  'cabify': Brand('C', Color(0xFF7038F5), domain: 'cabify.com'),
  'bilhunico': Brand('BU', Color(0xFF1E88E5)),
  'bilhete unico': Brand('BU', Color(0xFF1E88E5)),
  'shell': Brand('S', Color(0xFFED1C24), domain: 'shell.com.br'),
  'ipiranga': Brand('I', Color(0xFF0C4DA2), domain: 'ipiranga.com.br'),
  'petrobras': Brand('P', Color(0xFF00A08C), domain: 'petrobras.com.br'),
  'latam': Brand('L', Color(0xFF1B0088), domain: 'latamairlines.com'),
  'localiza': Brand('L', Color(0xFF00A650), domain: 'localiza.com'),

  // Compras
  'mercadolivre': Brand('ML', Color(0xFFE0AC00), domain: 'mercadolivre.com.br'),
  'mercado livre': Brand('ML', Color(0xFFE0AC00), domain: 'mercadolivre.com.br'),
  'melimais': Brand('ML', Color(0xFFE0AC00), domain: 'mercadolivre.com.br'),
  'mercadopago': Brand('MP', Color(0xFF00AEEF), domain: 'mercadopago.com.br'),
  'amazon': Brand('A', Color(0xFFFF9900), domain: 'amazon.com.br'),
  'shopee': Brand('S', Color(0xFFEE4D2D), domain: 'shopee.com.br'),
  'aliexpress': Brand('A', Color(0xFFE43225), domain: 'aliexpress.com'),
  'shein': Brand('S', Color(0xFF8A93A0), domain: 'shein.com'),
  'magalu': Brand('M', Color(0xFF0086FF), domain: 'magazineluiza.com.br'),
  'magazine': Brand('M', Color(0xFF0086FF), domain: 'magazineluiza.com.br'),
  'americanas': Brand('A', Color(0xFFE60014), domain: 'americanas.com.br'),
  'kabum': Brand('K', Color(0xFFFF6500), domain: 'kabum.com.br'),

  // Mercado
  'carrefour': Brand('C', Color(0xFF1565C0), domain: 'carrefour.com.br'),
  'assai': Brand('A', Color(0xFFFF6900), domain: 'assai.com.br'),
  'pao de acucar': Brand('PA', Color(0xFF00A650), domain: 'paodeacucar.com'),
  'atacad': Brand('A', Color(0xFFE53935)),
  'oxxo': Brand('O', Color(0xFFE31E24), domain: 'oxxo.com.br'),

  // Restaurantes
  'ifood': Brand('iF', Color(0xFFEA1D2C), domain: 'ifood.com.br'),
  'rappi': Brand('R', Color(0xFFFF441F), domain: 'rappi.com.br'),
  'mcdonald': Brand('M', Color(0xFFFFC72C), domain: 'mcdonalds.com.br'),
  'burger king': Brand('BK', Color(0xFFD62300), domain: 'burgerking.com.br'),
  'starbucks': Brand('S', Color(0xFF00704A), domain: 'starbucks.com.br'),
  'subway': Brand('S', Color(0xFF008C15), domain: 'subway.com'),
  'outback': Brand('O', Color(0xFFA6192E), domain: 'outback.com.br'),
  'madero': Brand('M', Color(0xFF8B0000), domain: 'restaurantemadero.com.br'),

  // Telefonia e internet
  'claro': Brand('C', Color(0xFFDA291C), domain: 'claro.com.br'),
  'vivo': Brand('V', Color(0xFF8B44C7), domain: 'vivo.com.br'),
  'tim': Brand('T', Color(0xFF2F6FD0), domain: 'tim.com.br'),
  'oi ': Brand('O', Color(0xFFF5A524), domain: 'oi.com.br'),

  // Tecnologia
  'google': Brand('G', Color(0xFF4285F4), domain: 'google.com'),
  'anthropic': Brand('C', Color(0xFFD97757), domain: 'anthropic.com'),
  'claude': Brand('C', Color(0xFFD97757), domain: 'claude.ai'),
  'openai': Brand('AI', Color(0xFF10A37F), domain: 'openai.com'),
  'chatgpt': Brand('AI', Color(0xFF10A37F), domain: 'openai.com'),
  'microsoft': Brand('M', Color(0xFF00A4EF), domain: 'microsoft.com'),
  'adobe': Brand('A', Color(0xFFED2224), domain: 'adobe.com'),
  'github': Brand('G', Color(0xFF8A93A0), domain: 'github.com'),
  'canva': Brand('C', Color(0xFF00C4CC), domain: 'canva.com'),
  'notion': Brand('N', Color(0xFF8A93A0), domain: 'notion.so'),
  'figma': Brand('F', Color(0xFFF24E1E), domain: 'figma.com'),
  'apple': Brand('A', Color(0xFF8A93A0), domain: 'apple.com'),
  'steam': Brand('S', Color(0xFF66C0F4), domain: 'steampowered.com'),
  'hostinger': Brand('H', Color(0xFF673DE6), domain: 'hostinger.com.br'),
  'perplexity': Brand('P', Color(0xFF20B8CD), domain: 'perplexity.ai'),

  // Pagamentos e bancos
  'picpay': Brand('P', Color(0xFF21C25E), domain: 'picpay.com'),
  'pagseguro': Brand('PS', Color(0xFF00A868), domain: 'pagseguro.uol.com.br'),
  'nubank': Brand('N', Color(0xFFA855F7), domain: 'nubank.com.br'),
  'itau': Brand('I', Color(0xFFEC7000), domain: 'itau.com.br'),
  'bradesco': Brand('B', Color(0xFFCC092F), domain: 'bradesco.com.br'),
  'santander': Brand('S', Color(0xFFEC0000), domain: 'santander.com.br'),
  'inter': Brand('I', Color(0xFFFF7A00), domain: 'bancointer.com.br'),

  // Educação e cursos
  'hotmart': Brand('H', Color(0xFFF04E23), domain: 'hotmart.com'),
  'udemy': Brand('U', Color(0xFFA435F0), domain: 'udemy.com'),
  'alura': Brand('A', Color(0xFF0F6FFF), domain: 'alura.com.br'),
  'kiwify': Brand('K', Color(0xFF00C853), domain: 'kiwify.com.br'),

  // Saúde e outros
  'drogasil': Brand('D', Color(0xFF00A94F), domain: 'drogasil.com.br'),
  'droga raia': Brand('R', Color(0xFF0075BE), domain: 'drogaraia.com.br'),
  'panvel': Brand('P', Color(0xFF00A0DF), domain: 'panvel.com'),
  'smartfit': Brand('SF', Color(0xFFFFD100), domain: 'smartfit.com.br'),
  'smart fit': Brand('SF', Color(0xFFFFD100), domain: 'smartfit.com.br'),
  'cinemark': Brand('C', Color(0xFF0F4C81), domain: 'cinemark.com.br'),
  'correios': Brand('C', Color(0xFFFFD100), domain: 'correios.com.br'),
};

/// Procura a marca pelo nome do estabelecimento, ignorando acentos e caixa.
Brand? brandFor(String? merchant) {
  if (merchant == null) return null;
  final texto = _normalize(merchant);
  if (texto.isEmpty) return null;

  for (final entry in _brands.entries) {
    if (texto.contains(entry.key)) return entry.value;
  }
  return null;
}

String _normalize(String input) {
  const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const semAcento = 'aaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final char in input.toLowerCase().split('')) {
    final index = comAcento.indexOf(char);
    buffer.write(index >= 0 ? semAcento[index] : char);
  }
  return buffer.toString();
}
