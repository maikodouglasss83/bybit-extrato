import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'widgets/common.dart';

/// Tela de entrada.
///
/// Entrar traz os dados dos outros aparelhos no mesmo clique. Continuar sem
/// conta também é caminho legítimo: o app inteiro funciona só com o
/// armazenamento local.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.state});

  final AppState state;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _entrando = false;
  String? _erro;

  Future<void> _entrarComGoogle() async {
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await widget.state.signInWithGoogle();
      // No navegador a página sai para o Google aqui e volta já autenticada.
    } catch (e) {
      if (mounted) {
        setState(() {
          _entrando = false;
          _erro = 'Não foi possível abrir o login do Google: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppColors.accent,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Extrato Bybit',
                    textAlign: TextAlign.center,
                    style: context.texts.displaySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Entre para ter seus ajustes, planejamento e histórico em '
                    'todos os aparelhos.',
                    textAlign: TextAlign.center,
                    style: context.texts.bodySmall,
                  ),
                  const SizedBox(height: 34),
                  _BotaoGoogle(
                    carregando: _entrando,
                    onPressed: _entrando ? null : _entrarComGoogle,
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 16),
                    ErrorBanner(message: _erro!),
                  ],
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _entrando ? null : widget.state.skipLogin,
                    child: const Text('Continuar sem conta'),
                  ),
                  const SizedBox(height: 30),
                  const _Garantias(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão no padrão visual do Google: fundo claro e o G colorido.
class _BotaoGoogle extends StatelessWidget {
  const _BotaoGoogle({required this.carregando, required this.onPressed});

  final bool carregando;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          disabledBackgroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: carregando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF1F1F1F),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _LogoGoogle(size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Entrar com Google',
                    style: context.texts.titleMedium?.copyWith(
                      color: const Color(0xFF1F1F1F),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// O "G" desenhado em quatro arcos, para não depender de imagem externa.
class _LogoGoogle extends StatelessWidget {
  const _LogoGoogle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.22;
    final arco = Rect.fromCircle(
      center: rect.center,
      radius: (size.width - stroke) / 2,
    );

    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Vermelho em cima, amarelo à esquerda, verde embaixo, azul à direita.
    canvas.drawArc(arco, -0.35, -1.6, false, p..color = const Color(0xFFEA4335));
    canvas.drawArc(arco, -1.95, -1.6, false, p..color = const Color(0xFFFBBC05));
    canvas.drawArc(arco, -3.55, -1.7, false, p..color = const Color(0xFF34A853));
    canvas.drawArc(arco, 1.15, -1.5, false, p..color = const Color(0xFF4285F4));

    // A barra horizontal do G.
    final barra = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.5,
        size.height * 0.5 - stroke / 2,
        size.width * 0.5 - stroke * 0.15,
        stroke,
      ),
      barra,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// O que o login faz e o que ele não faz.
class _Garantias extends StatelessWidget {
  const _Garantias();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.tones.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tones.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _linha(
            context,
            Icons.sync_rounded,
            'Ajustes, planejamento e histórico de compras acompanham você.',
          ),
          _linha(
            context,
            Icons.lock_outline_rounded,
            'A chave da Bybit não é sincronizada: fica só neste aparelho.',
          ),
          _linha(
            context,
            Icons.person_off_outlined,
            'Sem conta o app funciona igual, só que os dados não saem daqui.',
            ultima: true,
          ),
        ],
      ),
    );
  }

  Widget _linha(BuildContext context, IconData icone, String texto,
      {bool ultima = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultima ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 17, color: context.tones.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: context.texts.bodySmall)),
        ],
      ),
    );
  }
}
