import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'common.dart';

/// Cartão de sincronização: entrar, sair e acompanhar o estado.
class CloudCard extends StatefulWidget {
  const CloudCard({super.key, required this.state});

  final AppState state;

  @override
  State<CloudCard> createState() => _CloudCardState();
}

class _CloudCardState extends State<CloudCard> {
  final _emailController = TextEditingController();
  bool _enviando = false;
  String? _aviso;
  String? _erro;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _enviarLink() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _erro = 'Digite um e-mail válido.');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
      _aviso = null;
    });

    try {
      await widget.state.cloud.sendMagicLink(
        email,
        redirectTo: Uri.base.origin + Uri.base.path,
      );
      if (mounted) {
        setState(() => _aviso =
            'Link enviado para $email. Abra o e-mail neste aparelho para entrar.');
      }
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível enviar: $e');
    }

    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final tones = context.tones;

    // Sem projeto configurado o cartão explica em vez de sumir calado.
    if (!state.cloudAvailable) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Sincronização'),
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 20, color: tones.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Desligada nesta versão. Seus dados ficam só neste '
                    'aparelho.',
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Sincronização'),
          if (state.cloudSignedIn) ..._conectado(context, state) else ..._desconectado(context),
        ],
      ),
    );
  }

  List<Widget> _conectado(BuildContext context, AppState state) {
    final tones = context.tones;
    return [
      Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.cloud_done_rounded,
                color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sincronizando', style: context.texts.titleSmall),
                const SizedBox(height: 2),
                Text(
                  state.cloudEmail ?? '',
                  style: context.texts.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        state.cloudLastSync == null
            ? 'Ajustes, planejamento e histórico valem em todos os aparelhos.'
            : 'Última sincronização: ${fmtFullDate(state.cloudLastSync!)}',
        style: context.texts.bodySmall,
      ),
      if (state.cloudError != null) ...[
        const SizedBox(height: 12),
        ErrorBanner(message: state.cloudError!),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: state.cloudSyncing ? null : () => state.syncWithCloud(),
              icon: state.cloudSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(state.cloudSyncing ? 'Sincronizando…' : 'Sincronizar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await state.cloud.signOut();
                if (context.mounted) setState(() {});
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sair'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tones.negative,
                side: BorderSide(color: tones.negative.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _desconectado(BuildContext context) {
    return [
      Text(
        'Entre com seu e-mail para que apelidos, categorias, planejamento e o '
        'histórico de compras valham em todos os seus aparelhos.',
        style: context.texts.bodySmall,
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Seu e-mail',
          prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
        ),
        onSubmitted: (_) => _enviarLink(),
      ),
      if (_erro != null) ...[
        const SizedBox(height: 12),
        ErrorBanner(message: _erro!),
      ],
      if (_aviso != null) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_aviso!, style: context.texts.bodySmall),
            ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _enviando ? null : _enviarLink,
          child: _enviando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Color(0xFF04211A),
                  ),
                )
              : const Text('Receber link de acesso'),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: context.tones.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sua chave da Bybit não é sincronizada: ela continua só neste '
              'aparelho, e você a digita uma vez em cada um.',
              style: context.texts.bodySmall,
            ),
          ),
        ],
      ),
    ];
  }
}
