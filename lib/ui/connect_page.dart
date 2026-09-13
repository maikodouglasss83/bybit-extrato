import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/credentials.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/common.dart';

/// Abre a tela de conexão por cima da atual, para trocar a chave.
Future<void> openConnectPage(BuildContext context, AppState state) {
  return Navigator.of(context).push(
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

/// Tela de conexão: recebe a API Key e o Secret e valida na Bybit.
///
/// No computador o formulário fica ao lado do passo a passo, para quem cria
/// a chave numa aba e cola na outra não perder o fio. No celular o passo a
/// passo vem logo abaixo do formulário.
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

  /// Cola o que estiver copiado. O navegador pode negar a leitura — aí o
  /// caminho é o Ctrl+V de sempre, e a mensagem diz isso.
  Future<void> _colar(TextEditingController controller) async {
    try {
      final dados = await Clipboard.getData(Clipboard.kTextPlain);
      final texto = dados?.text?.trim() ?? '';
      if (texto.isEmpty) throw StateError('área de transferência vazia');
      controller.text = texto;
      controller.selection = TextSelection.collapsed(offset: texto.length);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não consegui ler o que foi copiado. Clique no campo e cole com '
            'Ctrl+V (ou segure e toque em Colar, no celular).',
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    final chave = _keyController.text.trim();
    final segredo = _secretController.text.trim();
    if (chave.isEmpty || segredo.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final error = await widget.state.connect(
      Credentials(apiKey: chave, apiSecret: segredo, testnet: _testnet),
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error != null) return;

    _secretController.clear();
    final aviso = widget.state.connectWarning;
    final mensageiro = ScaffoldMessenger.of(context);
    widget.onDone?.call();
    mensageiro.showSnackBar(
      SnackBar(content: Text(aviso ?? 'Conta conectada. Chave somente leitura.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largo = constraints.maxWidth >= 880;

        if (largo) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 36, 32, 44),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 10, child: _formulario(context, largo)),
                    const SizedBox(width: 56),
                    const Expanded(flex: 11, child: _PassoAPasso()),
                  ],
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _formulario(context, largo),
                  const SizedBox(height: 32),
                  const _PassoAPasso(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formulario(BuildContext context, bool largo) {
    final state = widget.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Conecte sua conta Bybit', style: context.texts.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Cole uma chave de API somente leitura. O app confere o que ela '
          'libera antes de guardar.',
          style: context.texts.bodySmall,
        ),
        if (state.credentials != null && state.apiKeyInfo != null) ...[
          const SizedBox(height: 20),
          KeyStatusCard(state: state),
        ],
        const SizedBox(height: 26),
        Text('API Key', style: context.texts.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _keyController,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'Cole a chave aqui',
            suffixIcon: _BotaoColar(onTap: () => _colar(_keyController)),
          ),
        ),
        const SizedBox(height: 18),
        Text('API Secret', style: context.texts.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _secretController,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: _obscureSecret,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Cole o secret aqui',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _obscureSecret ? 'Mostrar' : 'Esconder',
                  icon: Icon(
                    _obscureSecret
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                  ),
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                ),
                _BotaoColar(onTap: () => _colar(_secretController)),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 22),
        ListenableBuilder(
          listenable: Listenable.merge([_keyController, _secretController]),
          builder: (context, _) {
            final pronto = _keyController.text.trim().isNotEmpty &&
                _secretController.text.trim().isNotEmpty;
            final botao = FilledButton(
              onPressed: pronto && !_busy ? _submit : null,
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
            );
            return largo
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: 240, child: botao),
                  )
                : botao;
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Checkbox(
              value: _testnet,
              onChanged: (v) => setState(() => _testnet = v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Flexible(
              child: Text(
                'Usar a testnet da Bybit (ambiente de testes)',
                style: context.texts.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _Garantia(
          icone: Icons.shield_outlined,
          titulo: 'Conexão segura',
          texto: 'A chave fica criptografada neste aparelho, e as consultas '
              'vão direto para api.bybit.com, sem servidor no meio.',
        ),
        const SizedBox(height: 10),
        const _Garantia(
          icone: Icons.visibility_outlined,
          titulo: 'Somente leitura',
          texto: 'O app confere a chave ao conectar e recusa qualquer uma que '
              'possa negociar ou sacar.',
        ),
        const SizedBox(height: 10),
        const _Garantia(
          icone: Icons.admin_panel_settings_outlined,
          titulo: 'Você no controle',
          texto: 'Apague a chave na Bybit a qualquer momento e o acesso do '
              'app acaba na hora.',
        ),
      ],
    );
  }
}

class _BotaoColar extends StatelessWidget {
  const _BotaoColar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: const Text(
          'Colar',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

/// Uma das garantias da conexão, em destaque logo abaixo do formulário.
class _Garantia extends StatelessWidget {
  const _Garantia({
    required this.icone,
    required this.titulo,
    required this.texto,
  });

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: context.texts.titleSmall),
                const SizedBox(height: 3),
                Text(texto, style: context.texts.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Como criar a chave na Bybit, na ordem em que os botões aparecem.
class _PassoAPasso extends StatelessWidget {
  const _PassoAPasso();

  /// O que está entre `**` sai em negrito: são os nomes que a pessoa vai
  /// procurar na tela da Bybit, que está em inglês.
  static const _passos = [
    'Entre na sua conta em **bybit.com**, de preferência pelo computador.',
    'Passe o mouse no **ícone do perfil**, no canto superior direito, e '
        'clique em **API**.',
    'Clique em **Create New Key** e escolha **System-generated API Keys**.',
    'Selecione **API Transaction**. A outra opção, de aplicativos de '
        'terceiros, é só para parceiros cadastrados na Bybit.',
    'Dê um nome que você reconheça depois, como **Extrato**.',
    'Em permissões, escolha **Read-Only**. Com ela, nenhuma caixa permite '
        'negociar nem sacar.',
    'Marque **Unified Trading**, **Assets** e a permissão do **cartão** — '
        'sem ela, as compras do Bybit Card não aparecem.',
    'Deixe o campo de **IP** em branco. O app roda no seu navegador, que não '
        'tem um IP fixo para prender a chave.',
    'Clique em **Submit** e confirme com o **código do e-mail** e o '
        '**Google Authenticator**.',
    'Copie a **API Key** e a **API Secret** e cole nos campos desta tela. A '
        'Secret aparece uma vez só.',
  ];

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Passo a passo', style: context.texts.titleMedium),
        const SizedBox(height: 16),
        for (var i = 0; i < _passos.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tones.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tones.border),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: context.texts.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.colors.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _TextoComDestaque(_passos[i])),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tones.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tones.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_bottom_rounded, size: 18, color: tones.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A Bybit faz vencer em 90 dias toda chave sem IP fixo. O app '
                  'avisa ${AppState.keyWarningDays} dias antes, e trocar leva '
                  'dois minutos: é só repetir estes passos.',
                  style: context.texts.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Texto com os trechos entre `**` em negrito.
class _TextoComDestaque extends StatelessWidget {
  const _TextoComDestaque(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final base = context.texts.bodyMedium?.copyWith(
      color: context.tones.muted,
      height: 1.45,
    );
    final partes = texto.split('**');

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (var i = 0; i < partes.length; i++)
            TextSpan(
              text: partes[i],
              // As partes ímpares estavam entre os asteriscos.
              style: i.isOdd
                  ? TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.colors.onSurface,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

/// Situação da chave conectada: se é só de leitura, se lê o cartão e quando
/// vence.
class KeyStatusCard extends StatelessWidget {
  const KeyStatusCard({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final info = state.apiKeyInfo;
    if (info == null) return const SizedBox.shrink();

    final tones = context.tones;
    final dias = state.keyDaysLeft;
    final vence = info.expiresAt;

    final String vencimento;
    if (vence == null || dias == null) {
      vencimento = 'Não vence: a chave está presa a um IP';
    } else if (dias < 0) {
      vencimento = 'Venceu em ${fmtShortDate(vence.toLocal())}';
    } else if (dias == 0) {
      vencimento = 'Vence hoje';
    } else {
      vencimento = 'Vence em $dias ${dias == 1 ? 'dia' : 'dias'} · '
          '${fmtShortDate(vence.toLocal())}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tones.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tones.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LinhaDeSituacao(
            icone: info.readOnly
                ? Icons.verified_user_outlined
                : Icons.gpp_maybe_outlined,
            cor: info.readOnly ? tones.positive : tones.negative,
            texto: info.readOnly
                ? 'Somente leitura${info.note == null ? '' : ' · ${info.note}'}'
                : 'Pode negociar — troque por uma chave somente leitura',
          ),
          if (!info.canReadCard)
            const _LinhaDeSituacao(
              icone: Icons.credit_card_off_outlined,
              cor: AppColors.warning,
              texto: 'Sem a permissão do cartão: as compras não aparecem',
            ),
          _LinhaDeSituacao(
            icone: state.keyExpiresSoon
                ? Icons.event_busy_rounded
                : Icons.event_available_rounded,
            cor: state.keyExpiresSoon ? AppColors.warning : tones.muted,
            texto: vencimento,
          ),
        ],
      ),
    );
  }
}

class _LinhaDeSituacao extends StatelessWidget {
  const _LinhaDeSituacao({
    required this.icone,
    required this.cor,
    required this.texto,
  });

  final IconData icone;
  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icone, size: 17, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de que a chave está para vencer, com o atalho para trocar.
class KeyExpiryBanner extends StatelessWidget {
  const KeyExpiryBanner({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final dias = state.keyDaysLeft;
    if (!state.keyExpiresSoon || dias == null) return const SizedBox.shrink();

    final texto = dias < 0
        ? 'Sua chave da Bybit venceu. Crie outra para o app voltar a atualizar.'
        : dias == 0
            ? 'Sua chave da Bybit vence hoje. Troque agora para não parar de '
                'atualizar.'
            : 'Sua chave da Bybit vence em $dias ${dias == 1 ? 'dia' : 'dias'}. '
                'Troque antes para não parar de atualizar.';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_bottom_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: context.texts.bodySmall)),
          TextButton(
            onPressed: () => openConnectPage(context, state),
            child: const Text('Trocar chave'),
          ),
        ],
      ),
    );
  }
}
