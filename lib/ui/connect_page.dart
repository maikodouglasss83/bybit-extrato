import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/credentials.dart';
import '../theme.dart';
import 'widgets/common.dart';

/// Tela de conexão: recebe a API Key e o Secret e valida na Bybit.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.state, this.onDone});

  final AppState state;
  final VoidCallback? onDone;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _keyController = TextEditingController();
  final _secretController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _testnet = false;
  bool _obscureSecret = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.state.credentials;
    if (existing != null) {
      _keyController.text = existing.apiKey;
      _testnet = existing.testnet;
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final error = await widget.state.connect(
      Credentials(
        apiKey: _keyController.text,
        apiSecret: _secretController.text,
        testnet: _testnet,
      ),
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });

    if (error == null) {
      _secretController.clear();
      widget.onDone?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta conectada com sucesso.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: AppColors.accent, size: 28),
                ),
                const SizedBox(height: 20),
                Text('Conecte sua conta Bybit',
                    style: context.texts.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Suas credenciais ficam guardadas apenas neste dispositivo, '
                  'de forma criptografada. O app só lê os dados — nunca opera '
                  'nem movimenta a conta.',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 26),
                TextFormField(
                  controller: _keyController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: 'Cole a chave gerada na Bybit',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe a API Key' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _secretController,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: _obscureSecret,
                  decoration: InputDecoration(
                    labelText: 'API Secret',
                    hintText: 'Só é exibido uma vez na Bybit',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureSecret
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureSecret = !_obscureSecret),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o API Secret'
                      : null,
                ),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  value: _testnet,
                  onChanged: (v) => setState(() => _testnet = v),
                  contentPadding: EdgeInsets.zero,
                  title: Text('Usar testnet', style: context.texts.bodyMedium),
                  subtitle: Text(
                    'Ambiente de testes da Bybit',
                    style: context.texts.bodySmall,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Color(0xFF04211A),
                          ),
                        )
                      : const Text('Conectar'),
                ),
                const SizedBox(height: 22),
                const _SecurityNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tones.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tones.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: context.tones.muted),
              const SizedBox(width: 8),
              Text('Como gerar a chave com segurança',
                  style: context.texts.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Na Bybit, vá em Perfil › API e crie uma chave do tipo '
            '"System-generated". Marque somente as permissões de leitura '
            '(Wallet e Assets). Não habilite Trade nem Withdraw — o app não '
            'precisa delas.',
            style: context.texts.bodySmall,
          ),
        ],
      ),
    );
  }
}
