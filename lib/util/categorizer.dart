/// Categorização automática das compras do cartão.
///
/// A Bybit devolve o campo de categoria vazio, então a classificação é
/// deduzida do nome do estabelecimento. A ordem das regras importa: a
/// primeira que casar vence, por isso os casos específicos vêm antes dos
/// genéricos (por exemplo "amazonprime" antes de "amazon", e "mercadolivre"
/// antes de "mercado").
library;

class _Rule {
  const _Rule(this.category, this.keywords);
  final String category;
  final List<String> keywords;
}

/// Nomes das categorias, para manter a grafia consistente na interface.
class SpendCategories {
  static const assinaturas = 'Assinaturas';
  static const telefonia = 'Telefonia e internet';
  static const transporte = 'Transporte';
  static const mercado = 'Mercado';
  static const restaurantes = 'Restaurantes';
  static const compras = 'Compras';
  static const tecnologia = 'Tecnologia';
  static const saude = 'Saúde';
  static const educacao = 'Educação';
  static const lazer = 'Lazer';
  static const vestuario = 'Vestuário';
  static const casa = 'Casa';
  static const servicos = 'Serviços';
  static const transferencias = 'Transferências';
  static const outros = 'Outros';

  /// Categorias que costumam ser compromisso mensal: chegam todo mês, com
  /// valor parecido, e não dependem de escolha do dia a dia.
  ///
  /// É só o palpite inicial — o usuário marca ou desmarca o que quiser, e a
  /// escolha dele sempre vence.
  static const fixasPorPadrao = <String>{
    assinaturas,
    telefonia,
    casa,
    educacao,
  };

  /// Todas as categorias, na ordem em que aparecem no seletor.
  static const all = <String>[
    mercado,
    restaurantes,
    transporte,
    assinaturas,
    telefonia,
    compras,
    tecnologia,
    saude,
    educacao,
    lazer,
    vestuario,
    casa,
    servicos,
    transferencias,
    outros,
  ];
}

const _rules = <_Rule>[
  // Assinaturas digitais — vêm antes de "compras" porque muitas carregam
  // o nome da loja (AmazonPrime, Google Play).
  _Rule(SpendCategories.assinaturas, [
    'netflix', 'spotify', 'amazonprime', 'prime video', 'primevideo',
    'disney', 'hbo', 'globoplay', 'paramount', 'crunchyroll', 'deezer',
    'youtube', 'ytb', 'tinder', 'gotinder', 'apple.com/bill', 'itunes',
    'google play', 'googleplay', 'playstation', 'xbox', 'twitch',
    'onemembership', 'one membership', 'uber one',
  ]),

  _Rule(SpendCategories.telefonia, [
    'claro', 'vivo', 'tim*', 'tim ', 'oi fibra', 'nextel', 'algar',
    'fatura claro', 'net pgt', 'sky', 'telefonica', 'internet',
  ]),

  _Rule(SpendCategories.transporte, [
    'uber', '99app', '99 pop', '99pop', 'cabify', 'indriver',
    'bilhunico', 'bilhete unico', 'metro', 'cptm', 'sptrans', 'riocard',
    'posto', 'shell', 'ipiranga', 'petrobras', 'br mania', 'alesat',
    'estacionamento', 'parking', 'estapar', 'buser', 'clickbus',
    'latam', 'gol linhas', 'azul linhas', 'localiza', 'movida', 'unidas',
    'pedagio', 'sem parar', 'conectcar', 'veloe',
  ]),

  // E-commerce antes de mercado, senão "MercadoLivre" cairia em supermercado.
  _Rule(SpendCategories.compras, [
    'mercadolivre', 'mercado livre', 'melimais', 'mercadopago', 'meli',
    'amazon', 'shopee', 'aliexpress', 'shein', 'magazine', 'magalu',
    'americanas', 'submarino', 'casas bahia', 'kabum', 'temu',
  ]),

  _Rule(SpendCategories.mercado, [
    'mercadinho', 'supermercado', 'mercado', 'atacad', 'assai', 'assaí',
    'carrefour', 'pao de acucar', 'pão de açúcar', 'extra ', 'sonda',
    'hortifruti', 'padaria', 'acougue', 'açougue', 'emporio', 'empório',
    'sacolao', 'quitanda', 'minimercado', 'tenda', 'dia %', 'oxxo',
  ]),

  _Rule(SpendCategories.restaurantes, [
    'ifood', 'rappi', 'restaurante', 'lanchonete', 'pizza', 'burger',
    'mcdonald', 'mc donalds', 'bk ', 'burger king', 'subway', 'starbucks',
    'cafe', 'café', 'bar ', 'boteco', 'churrascaria', 'sushi', 'habib',
    'outback', 'giraffas', 'spoleto', 'coco bambu', 'madero', 'espetinho',
    'pastel', 'acai', 'açaí', 'sorvete', 'doceria', 'confeitaria',
  ]),

  _Rule(SpendCategories.tecnologia, [
    'anthropic', 'claude', 'openai', 'chatgpt', 'google', 'microsoft',
    'adobe', 'github', 'gitlab', 'aws', 'amazon web', 'cloudflare',
    'digitalocean', 'hostinger', 'hostgator', 'godaddy', 'registro.br',
    'canva', 'notion', 'figma', 'slack', 'zoom', 'dropbox', 'jetbrains',
    'inteligncia arti', 'inteligência arti', 'vercel', 'netlify',
    'supabase', 'firebase', 'perplexity', 'midjourney', 'cursor',
  ]),

  _Rule(SpendCategories.saude, [
    'farmacia', 'farmácia', 'drogaria', 'droga raia', 'drogasil',
    'pacheco', 'panvel', 'pague menos', 'hospital', 'clinica', 'clínica',
    'laboratorio', 'laboratório', 'unimed', 'amil', 'odonto', 'dentista',
    'psicolog', 'terapia', 'fisioterapia', 'otica', 'ótica', 'oftalmo',
  ]),

  _Rule(SpendCategories.educacao, [
    'curso', 'faculdade', 'universidade', 'escola', 'colegio', 'colégio',
    'udemy', 'alura', 'coursera', 'hotmart', 'kiwify', 'eduzz',
    'livraria', 'papelaria', 'kumon', 'wizard', 'fisk',
  ]),

  _Rule(SpendCategories.lazer, [
    'cinema', 'cinemark', 'kinoplex', 'ingresso', 'teatro', 'show',
    'academia', 'smartfit', 'smart fit', 'gympass', 'totalpass',
    'espaco', 'espaço', 'clube', 'parque', 'ticketmaster', 'sympla',
    'steam', 'epic games', 'nintendo', 'riot',
  ]),

  _Rule(SpendCategories.vestuario, [
    'renner', 'riachuelo', 'c&a', 'cea ', 'zara', 'hering', 'nike',
    'adidas', 'centauro', 'decathlon', 'netshoes', 'calcados', 'calçados',
    'moda', 'boutique', 'jeans',
  ]),

  _Rule(SpendCategories.casa, [
    'leroy', 'telhanorte', 'ikea', 'tok stok', 'mobly', 'madeiramadeira',
    'construcao', 'construção', 'material de constru', 'eletricidade',
    'enel', 'cemig', 'copel', 'light ', 'sabesp', 'comgas', 'aluguel',
    'condominio', 'condomínio',
  ]),

  _Rule(SpendCategories.servicos, [
    'pagseguro', 'pg *', 'picpay', 'stone', 'cielo', 'getnet', 'sumup',
    'infinitepay', 'seguro', 'porto seguro', 'cartorio', 'cartório',
    'correios', 'lavanderia', 'barbearia', 'salao', 'salão', 'cabeleireiro',
  ]),
];

/// Nomes de pessoa física costumam ser transferências, não compras.
final _pessoaFisica = RegExp(
  r'^[A-ZÁÂÃÀÉÊÍÓÔÕÚÇ]{3,}( [A-ZÁÂÃÀÉÊÍÓÔÕÚÇ]{2,}){2,}$',
);

/// Deduz a categoria a partir do nome do estabelecimento.
///
/// [apiCategory] tem prioridade: se algum dia a Bybit passar a preencher o
/// campo, o valor dela é respeitado.
String categorizeMerchant(String? merchant, {String? apiCategory}) {
  final fromApi = apiCategory?.trim();
  if (fromApi != null && fromApi.isNotEmpty) return fromApi;

  final raw = merchant?.trim() ?? '';
  if (raw.isEmpty) return SpendCategories.outros;

  final texto = _normalize(raw);
  for (final rule in _rules) {
    for (final keyword in rule.keywords) {
      if (texto.contains(_normalize(keyword))) return rule.category;
    }
  }

  if (_pessoaFisica.hasMatch(raw)) return SpendCategories.transferencias;
  return SpendCategories.outros;
}

/// Remove acentos e uniformiza a caixa, para as comparações não dependerem
/// de como o estabelecimento escreveu o nome.
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
