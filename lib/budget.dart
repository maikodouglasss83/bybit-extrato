// Estrutura do planejamento financeiro: categorias, subcategorias e metas.

import 'util/categorizer.dart';

/// Um nó do planejamento. Categorias principais têm [parentId] nulo;
/// subcategorias apontam para a principal.
class BudgetNode {
  const BudgetNode({
    required this.id,
    required this.name,
    this.parentId,
    this.budget = 0,
    this.sources = const [],
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String? parentId;

  /// Meta mensal em reais. Zero significa "sem meta definida".
  final double budget;

  /// Categorias automáticas de gasto que alimentam este nó. É o que liga o
  /// planejamento às compras reais do cartão.
  final List<String> sources;

  /// Nós da estrutura padrão não podem ser apagados, só editados.
  final bool builtIn;

  bool get isMain => parentId == null;

  BudgetNode copyWith({
    String? name,
    double? budget,
    List<String>? sources,
  }) =>
      BudgetNode(
        id: id,
        name: name ?? this.name,
        parentId: parentId,
        budget: budget ?? this.budget,
        sources: sources ?? this.sources,
        builtIn: builtIn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (parentId != null) 'parentId': parentId,
        'budget': budget,
        'sources': sources,
        'builtIn': builtIn,
      };

  factory BudgetNode.fromJson(Map<String, dynamic> j) => BudgetNode(
        id: j['id'].toString(),
        name: j['name'].toString(),
        parentId: j['parentId']?.toString(),
        budget: (j['budget'] as num?)?.toDouble() ?? 0,
        sources: ((j['sources'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        builtIn: j['builtIn'] == true,
      );
}

/// Identificador do nó que recolhe tudo que não se encaixou em nenhum outro.
const kUncategorizedId = 'sem_categoria';

/// Estrutura inicial, com as subcategorias já ligadas às categorias que o
/// app deduz das compras — assim o planejamento nasce com dados de verdade.
List<BudgetNode> defaultBudgetTree() => const [
      BudgetNode(id: 'casa', name: 'Casa', builtIn: true),
      BudgetNode(
        id: 'casa_moradia',
        name: 'Moradia e contas',
        parentId: 'casa',
        sources: [SpendCategories.casa],
        builtIn: true,
      ),

      BudgetNode(id: 'educacao', name: 'Educação', builtIn: true),
      BudgetNode(
        id: 'educacao_cursos',
        name: 'Cursos e materiais',
        parentId: 'educacao',
        sources: [SpendCategories.educacao],
        builtIn: true,
      ),

      BudgetNode(id: 'lazer', name: 'Lazer', builtIn: true),
      BudgetNode(
        id: 'lazer_assinaturas',
        name: 'Assinaturas',
        parentId: 'lazer',
        sources: [SpendCategories.assinaturas],
        builtIn: true,
      ),
      BudgetNode(
        id: 'lazer_diversao',
        name: 'Diversão',
        parentId: 'lazer',
        sources: [SpendCategories.lazer],
        builtIn: true,
      ),

      BudgetNode(id: 'saude', name: 'Saúde', builtIn: true),
      BudgetNode(
        id: 'saude_geral',
        name: 'Consultas e farmácia',
        parentId: 'saude',
        sources: [SpendCategories.saude],
        builtIn: true,
      ),

      BudgetNode(id: 'alimentacao', name: 'Alimentação', builtIn: true),
      BudgetNode(
        id: 'alimentacao_mercado',
        name: 'Mercado',
        parentId: 'alimentacao',
        sources: [SpendCategories.mercado],
        builtIn: true,
      ),
      BudgetNode(
        id: 'alimentacao_restaurantes',
        name: 'Restaurantes e delivery',
        parentId: 'alimentacao',
        sources: [SpendCategories.restaurantes],
        builtIn: true,
      ),

      BudgetNode(id: 'transporte', name: 'Transporte', builtIn: true),
      BudgetNode(
        id: 'transporte_geral',
        name: 'Deslocamento',
        parentId: 'transporte',
        sources: [SpendCategories.transporte],
        builtIn: true,
      ),

      BudgetNode(id: 'pessoais', name: 'Despesas pessoais', builtIn: true),
      BudgetNode(
        id: 'pessoais_compras',
        name: 'Compras',
        parentId: 'pessoais',
        sources: [SpendCategories.compras],
        builtIn: true,
      ),
      BudgetNode(
        id: 'pessoais_tecnologia',
        name: 'Tecnologia',
        parentId: 'pessoais',
        sources: [SpendCategories.tecnologia],
        builtIn: true,
      ),
      BudgetNode(
        id: 'pessoais_vestuario',
        name: 'Vestuário',
        parentId: 'pessoais',
        sources: [SpendCategories.vestuario],
        builtIn: true,
      ),

      BudgetNode(id: 'comunicacao', name: 'Comunicação', builtIn: true),
      BudgetNode(
        id: 'comunicacao_telefonia',
        name: 'Telefone e internet',
        parentId: 'comunicacao',
        sources: [SpendCategories.telefonia],
        builtIn: true,
      ),

      BudgetNode(id: 'tarifas', name: 'Tarifas e impostos', builtIn: true),
      BudgetNode(
        id: 'tarifas_servicos',
        name: 'Serviços e tarifas',
        parentId: 'tarifas',
        sources: [SpendCategories.servicos],
        builtIn: true,
      ),

      BudgetNode(id: 'outros', name: 'Outros', builtIn: true),
      BudgetNode(
        id: 'outros_transferencias',
        name: 'Transferências',
        parentId: 'outros',
        sources: [SpendCategories.transferencias],
        builtIn: true,
      ),
      BudgetNode(
        id: 'outros_diversos',
        name: 'Diversos',
        parentId: 'outros',
        sources: [SpendCategories.outros],
        builtIn: true,
      ),

      // Recolhe o que não estiver ligado a nenhum nó, para nenhum gasto
      // sumir do planejamento.
      BudgetNode(id: kUncategorizedId, name: 'Sem categoria', builtIn: true),
    ];

/// A categoria de gasto que pode voltar para uma subcategoria vazia, ou nulo.
///
/// Uma versão anterior deixava a criação de uma subcategoria levar, sem
/// avisar, a única categoria de outra: foi assim que "Mercado" ficou vazia
/// quando "Padaria" foi criada levando "Mercado" junto. Vazia, a subcategoria
/// continua na tela, mas nenhum gasto consegue cair nela.
///
/// Não há como saber se levar a categoria foi de propósito, então nada volta
/// sozinho: a tela oferece trazer de volta, e a pessoa decide. Para as
/// subcategorias padrão, volta a categoria de fábrica; para as criadas pela
/// pessoa, o próprio nome. E só quando quem a segura hoje fica com pelo menos
/// uma outra — nunca se esvazia um nó para encher outro.
String? restorableSource(List<BudgetNode> nodes, BudgetNode node) {
  if (node.isMain || node.sources.isNotEmpty) return null;

  final String? candidata;
  if (node.builtIn) {
    final padrao = defaultBudgetTree().where((n) => n.id == node.id).firstOrNull;
    candidata =
        padrao == null || padrao.sources.isEmpty ? null : padrao.sources.first;
  } else {
    candidata = node.name;
  }
  if (candidata == null) return null;

  final dono = nodes.where((n) => n.sources.contains(candidata)).firstOrNull;
  if (dono != null && dono.sources.length < 2) return null;
  return candidata;
}

/// Leva [source] para o nó [nodeId], tirando de quem a segurava — uma
/// categoria de gasto alimenta um nó só.
List<BudgetNode> withSourceMoved(
  List<BudgetNode> nodes,
  String nodeId,
  String source,
) =>
    [
      for (final n in nodes)
        if (n.id == nodeId)
          n.copyWith(sources: [...n.sources.where((s) => s != source), source])
        else if (n.sources.contains(source))
          n.copyWith(sources: n.sources.where((s) => s != source).toList())
        else
          n,
    ];

/// Quanto foi gasto e quanto foi planejado num nó.
class BudgetLine {
  const BudgetLine({
    required this.node,
    required this.spent,
    required this.budget,
    required this.children,
  });

  final BudgetNode node;

  /// Gasto do nó somado ao das subcategorias.
  final double spent;

  /// Meta que vale para o grupo.
  final double budget;

  final List<BudgetLine> children;

  bool get hasBudget => budget > 0;

  /// Quanto ainda cabe gastar. Negativo quando estourou.
  double get remaining => budget - spent;

  bool get exceeded => hasBudget && spent > budget;

  double get progress {
    if (budget <= 0) return 0;
    return (spent / budget).clamp(0.0, 1.0);
  }
}
