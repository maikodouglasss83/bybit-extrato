import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'connect_page.dart';
import 'widgets/common.dart';

/// Preferências, informações da conexão e gestão das credenciais.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AppState state;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final credentials = state.credentials;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Conexão'),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.link_rounded,
                        color: AppColors.accent, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          credentials == null ? 'Não conectado' : 'Bybit conectada',
                          style: context.texts.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          credentials == null
                              ? 'Adicione sua API Key para começar'
                              : 'Chave ${credentials.maskedKey}'
                                  '${credentials.testnet ? ' · testnet' : ''}',
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!state.credentialsPersisted) ...[
                const SizedBox(height: 14),
                ErrorBanner(
                  message: 'A chave não pôde ser guardada neste dispositivo: '
                      'o navegador só libera o cofre em endereços HTTPS. '
                      'Ela vale enquanto esta aba estiver aberta.',
                ),
              ],
              if (state.lastSync != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 15, color: context.tones.muted),
                    const SizedBox(width: 8),
                    Text(
                      'Última sincronização: ${fmtFullDate(state.lastSync!)}',
                      style: context.texts.bodySmall,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openConnect(context),
                      icon: const Icon(Icons.key_rounded, size: 18),
                      label: Text(credentials == null ? 'Conectar' : 'Trocar chave'),
                    ),
                  ),
                  if (credentials != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmDisconnect(context),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Desconectar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.tones.negative,
                          side: BorderSide(
                            color: context.tones.negative.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Exibição'),
              SwitchListTile.adaptive(
                value: state.showInBrl,
                onChanged: state.usdBrl == null
                    ? null
                    : (_) => state.toggleCurrency(),
                contentPadding: EdgeInsets.zero,
                title: Text('Mostrar valores em real',
                    style: context.texts.bodyMedium),
                subtitle: Text(
                  state.usdBrl == null
                      ? 'Cotação indisponível no momento'
                      : 'Dólar a ${fmtPlain(state.usdBrl!)}',
                  style: context.texts.bodySmall,
                ),
              ),
              SwitchListTile.adaptive(
                value: state.useOnlineLogos,
                onChanged: (_) => state.toggleOnlineLogos(),
                contentPadding: EdgeInsets.zero,
                title: Text('Baixar logos das marcas',
                    style: context.texts.bodyMedium),
                subtitle: Text(
                  state.useOnlineLogos
                      ? 'O nome do site de cada marca é enviado ao favicone.com '
                          'para buscar o logo.'
                      : 'Desligado: as marcas aparecem com a inicial na cor '
                          'delas, sem nenhuma requisição externa.',
                  style: context.texts.bodySmall,
                ),
              ),
              SwitchListTile.adaptive(
                value: state.hideBalances,
                onChanged: (_) => state.toggleHideBalances(),
                contentPadding: EdgeInsets.zero,
                title: Text('Ocultar saldos', style: context.texts.bodyMedium),
                subtitle: Text(
                  'Esconde os valores na tela',
                  style: context.texts.bodySmall,
                ),
              ),
              if (state.hiddenCount > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.visibility_off_rounded,
                      size: 20, color: context.tones.muted),
                  title: Text('Gastos ocultos', style: context.texts.bodyMedium),
                  subtitle: Text(
                    '${state.hiddenCount} '
                    '${state.hiddenCount == 1 ? 'lançamento aparece riscado' : 'lançamentos aparecem riscados'} '
                    'e fora dos totais.',
                    style: context.texts.bodySmall,
                  ),
                  trailing: TextButton(
                    onPressed: () => _confirmRestoreHidden(context),
                    child: const Text('Restaurar'),
                  ),
                ),
              if (state.customizedMerchantCount > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.push_pin_rounded,
                      size: 20, color: context.tones.muted),
                  title: Text('Ajustes seus', style: context.texts.bodyMedium),
                  subtitle: Text(
                    '${state.customizedMerchantCount} '
                    '${state.customizedMerchantCount == 1 ? 'estabelecimento' : 'estabelecimentos'} '
                    'com nome ou categoria personalizados',
                    style: context.texts.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              Text('Tema', style: context.texts.bodyMedium),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Sistema'),
                    icon: Icon(Icons.brightness_auto_rounded, size: 17),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Claro'),
                    icon: Icon(Icons.light_mode_rounded, size: 17),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Escuro'),
                    icon: Icon(Icons.dark_mode_rounded, size: 17),
                  ),
                ],
                selected: {themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onThemeModeChanged(s.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Segurança'),
              _bullet(context, Icons.visibility_off_outlined,
                  'A chave é usada apenas para leitura. O app não envia ordens nem saques.'),
              _bullet(context, Icons.phonelink_lock_outlined,
                  'As credenciais ficam no cofre criptografado deste dispositivo, sem servidor intermediário.'),
              _bullet(context, Icons.dns_outlined,
                  'As requisições vão direto do seu aparelho para api.bybit.com.'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Extrato Bybit · versão 1.0',
            style: context.texts.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _bullet(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.tones.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.texts.bodySmall)),
        ],
      ),
    );
  }

  void _openConnect(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: const Text('Chave da API')),
          body: ConnectPage(
            state: state,
            onDone: () => Navigator.of(routeContext).maybePop(),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestoreHidden(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar os gastos ocultos?'),
        content: Text(
          'Os ${state.hiddenCount} lançamentos ocultos voltam a contar nos '
          'totais e nos gráficos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.clearHidden();
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar a conta?'),
        content: const Text(
          'A API Key será apagada deste dispositivo. Os dados na Bybit não '
          'são afetados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.disconnect();
  }
}
