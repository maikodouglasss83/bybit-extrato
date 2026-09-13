import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'categories_page.dart';
import 'connect_page.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'planning_page.dart';
import 'settings_page.dart';
import 'statement_page.dart';
import 'subscriptions_page.dart';
import 'widgets/common.dart';

/// Estrutura de navegação: barra inferior no celular, lateral no computador.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.state,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AppState state;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// De onde o usuário veio ao abrir os ajustes, para o botão devolvê-lo ao
  /// mesmo lugar em vez de largá-lo na primeira aba.
  int _antesDosAjustes = 0;

  /// Barra lateral só com os ícones, para sobrar espaço para as tabelas.
  bool _menuRecolhido = false;

  static const _titles = [
    'Visão geral',
    'Gastos',
    'Assinaturas',
    'Planejamento',
    'Extrato',
    'Ajustes',
  ];
  static const _settingsIndex = 5;
  static const _statementIndex = 4;

  /// Abre os ajustes, ou fecha e volta para a página anterior.
  void _alternarAjustes() {
    setState(() {
      if (_index == _settingsIndex) {
        _index = _antesDosAjustes;
      } else {
        _antesDosAjustes = _index;
        _index = _settingsIndex;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (state.phase == LoadPhase.booting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // A entrada vem antes da chave da Bybit: quem já usa em outro aparelho
    // recupera tudo aqui, inclusive o histórico.
    if (state.needsLoginScreen) {
      return LoginPage(state: state);
    }

    if (state.phase == LoadPhase.needsSetup) {
      return Scaffold(body: SafeArea(child: ConnectPage(state: state)));
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = _buildBody(state);

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _SideNav(
                index: _index,
                onSelect: (i) => setState(() => _index = i),
                state: state,
                recolhido: _menuRecolhido,
                ajustesAbertos: _index == _settingsIndex,
                onAjustes: _alternarAjustes,
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: _titles[_index],
                      state: state,
                      menuRecolhido: _menuRecolhido,
                      onAlternarMenu: () =>
                          setState(() => _menuRecolhido = !_menuRecolhido),
                      showRefresh: _index != _settingsIndex,
                      settingsOpen: _index == _settingsIndex,
                      onSettings: _alternarAjustes,
                      themeMode: widget.themeMode,
                      onThemeModeChanged: widget.onThemeModeChanged,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1440),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final naDefinicoes = _index == _settingsIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (!naDefinicoes)
            IconButton(
              tooltip: 'Atualizar',
              onPressed: state.refresh,
              icon: state.phase == LoadPhase.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: naDefinicoes ? 'Fechar ajustes' : 'Ajustes',
            onPressed: _alternarAjustes,
            icon: Icon(
              naDefinicoes ? Icons.close_rounded : Icons.settings_outlined,
              color: naDefinicoes ? AppColors.accent : null,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        // Nos ajustes a barra mostra de onde se veio: eles não são uma aba,
        // e nenhum destino aceso seria pior do que o anterior aceso.
        selectedIndex: naDefinicoes ? _antesDosAjustes : _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Resumo',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Gastos',
          ),
          NavigationDestination(
            icon: Icon(Icons.autorenew_outlined),
            selectedIcon: Icon(Icons.autorenew_rounded),
            label: 'Assinaturas',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Planos',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Extrato',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppState state) {
    if (state.phase == LoadPhase.loading && state.lastSync == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.phase == LoadPhase.failed &&
        state.lastSync == null &&
        _index != _settingsIndex) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar',
        message: state.errorMessage ?? 'Erro desconhecido.',
        action: FilledButton(
          onPressed: state.refresh,
          child: const Text('Tentar de novo'),
        ),
      );
    }

    switch (_index) {
      case 0:
        return DashboardPage(
          state: state,
          onSeeStatement: () => setState(() => _index = _statementIndex),
          onSeeCategories: () => setState(() => _index = 1),
        );
      case 1:
        return CategoriesPage(state: state);
      case 2:
        return SubscriptionsPage(state: state);
      case 3:
        return PlanningPage(state: state);
      case 4:
        return StatementPage(state: state);
      default:
        return SettingsPage(
          state: state,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        );
    }
  }
}

/// Navegação lateral usada nas telas largas.
///
/// Os itens vêm agrupados por assunto: numa tela grande a lista corrida de
/// seis nomes não diz o que é consulta, o que é planejamento e o que é
/// ajuste — os títulos das seções fazem esse trabalho.
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.index,
    required this.onSelect,
    required this.state,
    required this.recolhido,
    required this.ajustesAbertos,
    required this.onAjustes,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final AppState state;
  final bool recolhido;
  final bool ajustesAbertos;
  final VoidCallback onAjustes;

  static const larguraAberta = 244.0;
  static const larguraRecolhida = 72.0;

  static const _secoes = <String, List<(int, IconData, String)>>{
    'GERAL': [
      (0, Icons.dashboard_rounded, 'Visão geral'),
      (4, Icons.receipt_long_rounded, 'Extrato'),
    ],
    'PLANEJAMENTO': [
      (2, Icons.autorenew_rounded, 'Assinaturas'),
      (3, Icons.flag_rounded, 'Planejamento'),
    ],
    'ANÁLISE': [
      (1, Icons.pie_chart_rounded, 'Gastos por categoria'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: recolhido ? larguraRecolhida : larguraAberta,
      color: context.colors.surface,
      // Durante a animação a largura passa por valores intermediários: os
      // textos só aparecem quando cabem, para não estourar no meio do caminho.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 200;
          return Padding(
            padding: EdgeInsets.symmetric(
              vertical: 20,
              horizontal: compacto ? 10 : 14,
            ),
            child: Column(
              crossAxisAlignment: compacto
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                _cabecalho(context, compacto),
                const SizedBox(height: 22),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final secao in _secoes.entries) ...[
                          if (compacto)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(height: 1, indent: 8, endIndent: 8),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                              child: Text(
                                secao.key,
                                style: context.texts.labelSmall,
                                maxLines: 1,
                              ),
                            ),
                          for (final (i, icone, rotulo) in secao.value)
                            _navItem(context, i, icone, rotulo, compacto),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24),
                _Assinante(
                  state: state,
                  compacto: compacto,
                  ajustesAbertos: ajustesAbertos,
                  onAjustes: onAjustes,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cabecalho(BuildContext context, bool compacto) {
    final logo = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(Icons.account_balance_wallet_rounded,
          size: 18, color: AppColors.accent),
    );

    if (compacto) return logo;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Extrato Bybit',
              style: context.texts.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    int i,
    IconData icon,
    String label,
    bool compacto,
  ) {
    final selected = index == i;
    final icone = Icon(icon,
        size: 19, color: selected ? AppColors.accent : context.tones.muted);

    final item = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onSelect(i),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 0 : 12,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: compacto
            ? Center(child: icone)
            : Row(
                children: [
                  icone,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected
                            ? context.colors.onSurface
                            : context.tones.muted,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // Recolhido, o nome da página aparece ao passar o mouse.
      child: compacto
          ? Tooltip(
              message: label,
              waitDuration: const Duration(milliseconds: 300),
              child: item,
            )
          : item,
    );
  }
}

/// Quadrado arredondado com a faixa da barra à esquerda.
class _IconeBarraLateral extends StatelessWidget {
  const _IconeBarraLateral({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 20,
      child: CustomPaint(painter: _PintorBarraLateral(color)),
    );
  }
}

class _PintorBarraLateral extends CustomPainter {
  const _PintorBarraLateral(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final caixa = Rect.fromLTWH(2, 3, size.width - 4, size.height - 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(caixa, const Radius.circular(3.5)),
      pincel,
    );
    final x = caixa.left + caixa.width * 0.36;
    canvas.drawLine(Offset(x, caixa.top), Offset(x, caixa.bottom), pincel);
  }

  @override
  bool shouldRepaint(_PintorBarraLateral old) => old.color != color;
}

/// Quem está usando o app, no pé da barra lateral, com o atalho dos ajustes.
///
/// Mostra o e-mail da conta conectada. A chave da Bybit não aparece aqui: nem
/// mascarada ela ajuda a identificar a conta, e fica à vista de quem olha a tela.
class _Assinante extends StatelessWidget {
  const _Assinante({
    required this.state,
    required this.ajustesAbertos,
    required this.onAjustes,
    this.compacto = false,
  });

  final AppState state;
  final bool compacto;
  final bool ajustesAbertos;
  final VoidCallback onAjustes;

  @override
  Widget build(BuildContext context) {
    final email = state.cloudEmail;
    final nome = state.cloudName ?? email;

    final ajustes = IconButton(
      tooltip: ajustesAbertos ? 'Fechar ajustes' : 'Ajustes',
      onPressed: onAjustes,
      icon: Icon(
        ajustesAbertos ? Icons.close_rounded : Icons.settings_outlined,
        size: 20,
        color: ajustesAbertos ? AppColors.accent : context.tones.muted,
      ),
    );

    final avatar = CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.accent.withValues(alpha: 0.18),
            backgroundImage: state.cloudAvatar == null
                ? null
                : NetworkImage(state.cloudAvatar!),
            child: state.cloudAvatar != null
                ? null
                : Icon(
                    nome == null ? Icons.vpn_key_rounded : Icons.person_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
          );

    if (compacto) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ajustes,
          const SizedBox(height: 6),
          Tooltip(
            message: [
              nome ?? 'Sem conta',
              if (email != null && email != nome) email,
            ].join('\n'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: avatar,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome ?? 'Sem conta',
                  style: context.texts.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (email != null && email != nome)
                  Text(
                    email,
                    style: context.texts.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          ajustes,
        ],
      ),
    );
  }
}

/// Faixa superior das telas largas: título à esquerda, ações à direita.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.state,
    required this.menuRecolhido,
    required this.onAlternarMenu,
    required this.showRefresh,
    required this.settingsOpen,
    required this.onSettings,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final String title;
  final AppState state;
  final bool menuRecolhido;
  final VoidCallback onAlternarMenu;
  final bool showRefresh;
  final bool settingsOpen;
  final VoidCallback onSettings;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final escuro = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 24, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: menuRecolhido ? 'Expandir menu' : 'Recolher menu',
            onPressed: onAlternarMenu,
            icon: _IconeBarraLateral(color: context.tones.muted),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              style: context.texts.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (showRefresh) ...[
            Text(_desdeASincronizacao(state), style: context.texts.bodySmall),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: state.refresh,
              icon: state.phase == LoadPhase.loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
          IconButton(
            tooltip: settingsOpen ? 'Fechar ajustes' : 'Ajustes',
            onPressed: onSettings,
            icon: Icon(
              settingsOpen ? Icons.close_rounded : Icons.settings_outlined,
              size: 20,
              color: settingsOpen ? AppColors.accent : null,
            ),
          ),
          IconButton(
            tooltip: state.hideBalances ? 'Mostrar valores' : 'Ocultar valores',
            onPressed: state.toggleHideBalances,
            icon: Icon(
              state.hideBalances
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: escuro ? 'Tema claro' : 'Tema escuro',
            onPressed: () => onThemeModeChanged(
              escuro ? ThemeMode.light : ThemeMode.dark,
            ),
            icon: Icon(
              escuro ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          _MoedaDoTopo(state: state),
        ],
      ),
    );
  }

  /// "agora", "há 5 min" ou o horário — o que for mais informativo.
  static String _desdeASincronizacao(AppState state) {
    final quando = state.lastSync;
    if (quando == null) return 'nunca sincronizado';
    final minutos = DateTime.now().difference(quando).inMinutes;
    if (minutos < 1) return 'agora';
    if (minutos < 60) return 'há $minutos min';
    return 'às ${fmtTime(quando)}';
  }
}

/// Troca a moeda de exibição sem sair da página.
class _MoedaDoTopo extends StatelessWidget {
  const _MoedaDoTopo({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.usdBrl == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: context.tones.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.tones.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _opcao(context, r'R$', state.showInBrl),
          _opcao(context, r'US$', !state.showInBrl),
        ],
      ),
    );
  }

  Widget _opcao(BuildContext context, String rotulo, bool ativa) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: ativa ? null : state.toggleCurrency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: ativa
              ? AppColors.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          rotulo,
          style: context.texts.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: ativa ? AppColors.accent : context.tones.muted,
          ),
        ),
      ),
    );
  }
}
