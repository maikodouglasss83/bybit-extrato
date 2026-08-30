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
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: _titles[_index],
                      state: state,
                      showRefresh: _index != _settingsIndex,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (_index != _settingsIndex)
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
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
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
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ajustes',
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
  });

  final int index;
  final ValueChanged<int> onSelect;
  final AppState state;

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
    'CONTA': [
      (5, Icons.settings_rounded, 'Ajustes'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 244,
      color: context.colors.surface,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Extrato Bybit',
                    style: context.texts.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final secao in _secoes.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Text(secao.key, style: context.texts.labelSmall),
                    ),
                    for (final (i, icone, rotulo) in secao.value)
                      _navItem(context, i, icone, rotulo),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 24),
          _Assinante(state: state),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, int i, IconData icon, String label) {
    final selected = index == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 19,
                  color: selected ? AppColors.accent : context.tones.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? context.colors.onSurface
                        : context.tones.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quem está usando o app, no pé da barra lateral.
class _Assinante extends StatelessWidget {
  const _Assinante({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final nome = state.cloudName ?? state.cloudEmail;
    final chave = state.credentials?.maskedKey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
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
          ),
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
                if (chave != null)
                  Text(
                    'Chave $chave',
                    style: context.texts.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
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
    required this.showRefresh,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final String title;
  final AppState state;
  final bool showRefresh;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final escuro = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      child: Row(
        children: [
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
