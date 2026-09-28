import 'package:flutter/material.dart';

import '../../theme.dart';
import 'common.dart';

/// Painel à direita, no computador, com o detalhe do que foi tocado na página.
///
/// A lista continua à vista e o detalhe troca a cada toque, em vez de uma
/// folha cobrindo a tela. Em telas estreitas não há espaço, e quem chama abre
/// a folha de baixo — [abrirAoLado] decide sozinho.
class PainelLateral extends StatefulWidget {
  const PainelLateral({super.key, required this.child});

  final Widget child;

  /// A partir daqui a página e o painel cabem lado a lado.
  static const larguraMinima = 1040.0;

  static const largura = 360.0;

  /// Mostra [conteudo] no painel mais próximo.
  ///
  /// Aberto pela página, começa do zero. Aberto de dentro do próprio painel —
  /// uma compra dentro da categoria, o editor dentro dos detalhes —, empilha
  /// sobre o que estava, e a seta de voltar leva de volta a ele.
  ///
  /// [aoFechar] roda quando o conteúdo sai do painel de vez: fechado, trocado
  /// por outro da página, desempilhado ou tirado por falta de espaço.
  /// Devolve `false` quando não coube.
  static bool abrir(
    BuildContext context, {
    required String titulo,
    required IconData icone,
    required WidgetBuilder conteudo,
    VoidCallback? aoFechar,
  }) {
    final painel = context.findAncestorStateOfType<_PainelLateralState>();
    if (painel == null || !painel._cabe) return false;
    painel._mostrar(
      _Aberto(titulo, icone, conteudo, aoFechar),
      empilhar: dentro(context),
    );
    return true;
  }

  /// Fecha o painel mais próximo, com tudo o que estava empilhado.
  /// Devolve `false` se não havia o que fechar.
  static bool fechar(BuildContext context) {
    final painel = context.findAncestorStateOfType<_PainelLateralState>();
    if (painel == null || painel._pilha.isEmpty) return false;
    painel._fechar();
    return true;
  }

  /// Volta para o conteúdo anterior; sem anterior, fecha o painel.
  static bool voltarOuFechar(BuildContext context) {
    final painel = context.findAncestorStateOfType<_PainelLateralState>();
    if (painel == null || painel._pilha.isEmpty) return false;
    painel._pilha.length > 1 ? painel._voltar() : painel._fechar();
    return true;
  }

  /// Se o painel ao lado da página está aberto — para a página se ajustar ao
  /// espaço que sobrou.
  static bool aberto(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PainelInfo>()?.aberto ??
      false;

  /// Se [context] está dentro do conteúdo do painel, e não numa folha.
  static bool dentro(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_DentroDoPainel>() != null;

  @override
  State<PainelLateral> createState() => _PainelLateralState();
}

class _Aberto {
  _Aberto(this.titulo, this.icone, this.conteudo, this.aoFechar);

  final String titulo;
  final IconData icone;
  final WidgetBuilder conteudo;
  final VoidCallback? aoFechar;

  /// Identidade na pilha: dois editores seguidos são telas diferentes, e o
  /// segundo não pode herdar os campos do primeiro.
  late final int id;
}

class _PainelLateralState extends State<PainelLateral> {
  /// O que está aberto, do primeiro ao que aparece por cima.
  final List<_Aberto> _pilha = [];
  bool _cabe = false;
  int _proximoId = 0;

  void _mostrar(_Aberto novo, {required bool empilhar}) {
    novo.id = _proximoId++;
    final saem = empilhar ? const <_Aberto>[] : List.of(_pilha);
    setState(() {
      if (!empilhar) _pilha.clear();
      _pilha.add(novo);
    });
    _avisar(saem);
  }

  void _voltar() {
    final sai = _pilha.last;
    setState(_pilha.removeLast);
    _avisar([sai]);
  }

  void _fechar() {
    final saem = List.of(_pilha);
    setState(_pilha.clear);
    _avisar(saem);
  }

  /// Avisa quem saiu, do que estava por cima para o de baixo.
  void _avisar(List<_Aberto> saem) {
    for (final a in saem.reversed) {
      a.aoFechar?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _cabe = constraints.maxWidth >= PainelLateral.larguraMinima;
        // Ao estreitar a janela o painel fecha, e não volta sozinho depois.
        if (!_cabe && _pilha.isNotEmpty) {
          final saem = List.of(_pilha);
          _pilha.clear();
          WidgetsBinding.instance.addPostFrameCallback((_) => _avisar(saem));
        }
        final aberto = _pilha.isEmpty ? null : _pilha.last;

        // Sempre uma linha, com a página no mesmo lugar: abrir o painel não
        // pode recriar a lista e jogar a rolagem de volta ao topo.
        return _PainelInfo(
          aberto: aberto != null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: widget.child),
              if (aberto != null) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: PainelLateral.largura,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              _pilha.length > 1 ? 6 : 20,
                              14,
                              10,
                              0,
                            ),
                            child: Row(
                              children: [
                                if (_pilha.length > 1) ...[
                                  IconButton(
                                    tooltip: 'Voltar',
                                    onPressed: _voltar,
                                    icon: const Icon(Icons.arrow_back_rounded,
                                        size: 20),
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                Icon(aberto.icone,
                                    size: 16, color: context.tones.muted),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    aberto.titulo,
                                    style: context.texts.labelSmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Fechar',
                                  onPressed: _fechar,
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _DentroDoPainel(
                              // Os de baixo continuam montados, só escondidos:
                              // ao voltar, a lista está onde foi deixada, com
                              // a mesma rolagem e o que estava aberto.
                              child: IndexedStack(
                                index: _pilha.length - 1,
                                sizing: StackFit.expand,
                                children: [
                                  for (final a in _pilha)
                                    KeyedSubtree(
                                      key: ValueKey(a.id),
                                      child: Builder(builder: a.conteudo),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PainelInfo extends InheritedWidget {
  const _PainelInfo({required this.aberto, required super.child});

  final bool aberto;

  @override
  bool updateShouldNotify(_PainelInfo old) => old.aberto != aberto;
}

class _DentroDoPainel extends InheritedWidget {
  const _DentroDoPainel({required super.child});

  @override
  bool updateShouldNotify(_DentroDoPainel old) => false;
}

/// Abre [conteudo] no painel ao lado, no computador, ou numa folha que sobe
/// de baixo, no celular e em janelas estreitas.
///
/// É o mesmo conteúdo nos dois lugares. Para uma lista que rola dentro da
/// folha, o conteúdo usa [FolhaOuPainel]; para fechar, [fecharDetalhe].
Future<void> abrirAoLado(
  BuildContext context, {
  required String titulo,
  required IconData icone,
  required WidgetBuilder conteudo,
  bool comTeclado = false,
  VoidCallback? aoFechar,
}) async {
  final noPainel = PainelLateral.abrir(
    context,
    titulo: titulo,
    icone: icone,
    conteudo: conteudo,
    aoFechar: aoFechar,
  );
  if (noPainel) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (folha) =>
        comTeclado ? AcimaDoTeclado(child: conteudo(folha)) : conteudo(folha),
  );
  aoFechar?.call();
}

/// Fecha o que foi aberto por [abrirAoLado]: no painel, volta para o que
/// estava antes, ou fecha se não havia nada; na folha, fecha a folha.
void fecharDetalhe(BuildContext context) {
  if (PainelLateral.dentro(context) && PainelLateral.voltarOuFechar(context)) {
    return;
  }
  Navigator.of(context).maybePop();
}

/// Rolagem arrastável na folha do celular; no painel, o conteúdo ocupa a
/// altura toda, que ali já é fixa.
class FolhaOuPainel extends StatelessWidget {
  const FolhaOuPainel({
    super.key,
    required this.builder,
    this.inicial = 0.7,
    this.maximo = 0.92,
  });

  /// Recebe a rolagem da folha, ou nulo no painel.
  final Widget Function(ScrollController? rolagem) builder;
  final double inicial;
  final double maximo;

  @override
  Widget build(BuildContext context) {
    if (PainelLateral.dentro(context)) return builder(null);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: inicial,
      maxChildSize: maximo,
      builder: (_, rolagem) => builder(rolagem),
    );
  }
}
