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

  /// Mostra [conteudo] no painel mais próximo, trocando o que estiver aberto.
  ///
  /// [aoFechar] roda quando o conteúdo sai do painel: fechado, trocado por
  /// outro ou tirado por falta de espaço. Devolve `false` quando não coube.
  static bool abrir(
    BuildContext context, {
    required String titulo,
    required IconData icone,
    required WidgetBuilder conteudo,
    VoidCallback? aoFechar,
  }) {
    final painel = context.findAncestorStateOfType<_PainelLateralState>();
    if (painel == null || !painel._cabe) return false;
    painel._mostrar(_Aberto(titulo, icone, conteudo, aoFechar));
    return true;
  }

  /// Fecha o painel mais próximo. Devolve `false` se não havia o que fechar.
  static bool fechar(BuildContext context) {
    final painel = context.findAncestorStateOfType<_PainelLateralState>();
    if (painel == null || painel._aberto == null) return false;
    painel._fechar();
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
  const _Aberto(this.titulo, this.icone, this.conteudo, this.aoFechar);

  final String titulo;
  final IconData icone;
  final WidgetBuilder conteudo;
  final VoidCallback? aoFechar;
}

class _PainelLateralState extends State<PainelLateral> {
  _Aberto? _aberto;
  bool _cabe = false;

  /// Muda a cada conteúdo novo: dois editores seguidos são telas diferentes,
  /// e o segundo não pode herdar os campos do primeiro.
  int _versao = 0;

  void _mostrar(_Aberto novo) {
    final anterior = _aberto;
    setState(() {
      _aberto = novo;
      _versao++;
    });
    anterior?.aoFechar?.call();
  }

  void _fechar() {
    final anterior = _aberto;
    setState(() => _aberto = null);
    anterior?.aoFechar?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _cabe = constraints.maxWidth >= PainelLateral.larguraMinima;
        // Ao estreitar a janela o painel fecha, e não volta sozinho depois.
        if (!_cabe && _aberto != null) {
          final aviso = _aberto!.aoFechar;
          _aberto = null;
          if (aviso != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => aviso());
          }
        }
        final aberto = _aberto;

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
                            padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
                            child: Row(
                              children: [
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
                              child: KeyedSubtree(
                                key: ValueKey(_versao),
                                child: Builder(builder: aberto.conteudo),
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

/// Fecha o que foi aberto por [abrirAoLado]: o painel, ou a folha.
void fecharDetalhe(BuildContext context) {
  if (PainelLateral.dentro(context) && PainelLateral.fechar(context)) return;
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
