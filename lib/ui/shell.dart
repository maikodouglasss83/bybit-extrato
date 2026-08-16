import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'categories_page.dart';
import 'connect_page.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'planning_page.dart';
import 'settings_page.dart';
import 'statement_page.dart';
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
    'Planejamento',
    'Extrato',
    'Ajustes',
  ];
  static const _settingsIndex = 4;

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
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
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
            label: 'Visão geral',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Gastos',
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
          onSeeStatement: () => setState(() => _index = 3),
          onSeeCategories: () => setState(() => _index = 1),
        );
      case 1:
        return CategoriesPage(state: state);
      case 2:
        return PlanningPage(state: state);
      case 3:
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
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.index,
    required this.onSelect,
    required this.state,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
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
          const SizedBox(height: 28),
          _navItem(context, 0, Icons.dashboard_rounded, 'Visão geral'),
          _navItem(context, 1, Icons.pie_chart_rounded, 'Gastos'),
          _navItem(context, 2, Icons.flag_rounded, 'Planejamento'),
          _navItem(context, 3, Icons.receipt_long_rounded, 'Extrato'),
          _navItem(context, 4, Icons.settings_rounded, 'Ajustes'),
          const Spacer(),
          if (state.credentials != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Chave ${state.credentials!.maskedKey}',
                style: context.texts.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, int i, IconData icon, String label) {
    final selected = index == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? AppColors.accent : context.tones.muted),
              const SizedBox(width: 12),
              Text(
                label,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? context.colors.onSurface : context.tones.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.state,
    required this.showRefresh,
  });

  final String title;
  final AppState state;
  final bool showRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        children: [
          Text(title, style: context.texts.headlineSmall),
          const Spacer(),
          if (showRefresh)
            OutlinedButton.icon(
              onPressed: state.refresh,
              icon: state.phase == LoadPhase.loading
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Atualizar'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
            ),
        ],
      ),
    );
  }
}
