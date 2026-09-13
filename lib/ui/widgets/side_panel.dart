import 'package:flutter/material.dart';

import '../../theme.dart';

/// Painel à direita, no computador, com o detalhe do que foi tocado na página.
///
/// É o mesmo cartão dos detalhes do extrato: a lista continua à vista e o
/// detalhe troca a cada toque, em vez de uma folha cobrindo a tela. Em telas
/// estreitas não há espaço, e quem chama abre a folha de baixo como antes.
class PainelLateral extends StatefulWidget {
  const PainelLateral({super.key, required this.child});

  final Widget child;

  /// A partir daqui a página e o painel cabem lado a lado.
  static const larguraMinima = 1040.0;

  static const largura = 340.0;

  /// Mostra [conteudo] no painel da página, trocando o que estiver aberto.
  ///
  /// Devolve `false` quando não coube, para quem chamou abrir a folha.
  static bool abrir(
    BuildContext context, {
    required String titulo,
    required IconData icone,
    required WidgetBuilder conteudo,
  }) {
    final painel = context.findAncestorStateOfType<_PainelLateralState>();
    if (painel == null || !painel._cabe) return false;
    painel._mostrar(_Aberto(titulo, icone, conteudo));
    return true;
  }

  @override
  State<PainelLateral> createState() => _PainelLateralState();
}

class _Aberto {
  const _Aberto(this.titulo, this.icone, this.conteudo);

  final String titulo;
  final IconData icone;
  final WidgetBuilder conteudo;
}

class _PainelLateralState extends State<PainelLateral> {
  _Aberto? _aberto;
  bool _cabe = false;

  void _mostrar(_Aberto aberto) => setState(() => _aberto = aberto);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _cabe = constraints.maxWidth >= PainelLateral.larguraMinima;
        // Ao estreitar a janela o painel fecha, e não volta sozinho depois.
        if (!_cabe) _aberto = null;
        final aberto = _aberto;

        // Sempre uma linha, com a página no mesmo lugar: abrir o painel não
        // pode recriar a lista e jogar a rolagem de volta ao topo.
        return Row(
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
                                onPressed: () =>
                                    setState(() => _aberto = null),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: Builder(builder: aberto.conteudo)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}
