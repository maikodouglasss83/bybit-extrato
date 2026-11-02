import 'package:flutter/material.dart';

/// Laranja da marca. Fixo, e não o acento do tema: o logo é o mesmo em
/// qualquer tema, na aba do navegador e no ícone da tela inicial.
const corDaMarca = Color(0xFFFF9F1A);

/// Tinta escura sobre o laranja da marca.
const tintaDaMarca = Color(0xFF1A1206);

/// Fundo escuro dos ícones gerados, o mesmo das superfícies do app.
const fundoDaMarca = Color(0xFF14171C);

/// Logo do ExtratoCripto: a carteira laranja sobre o quadrado em laranja
/// suave.
class LogoExtratoCripto extends StatelessWidget {
  const LogoExtratoCripto({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: corDaMarca.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        Icons.account_balance_wallet_rounded,
        size: size * 0.5,
        color: corDaMarca,
      ),
    );
  }
}

/// Desenha o logo para os ícones do app, numa grade de 24 unidades.
///
/// A carteira é traçada à mão porque os ícones são gerados sem a fonte de
/// ícones carregada. [cheio] pinta o quadrado inteiro, sem cantos
/// arredondados: é o que os ícones "maskable" pedem, porque o sistema recorta
/// a forma que quiser. [escala] muda o tamanho da carteira dentro do quadrado.
class PintorDoLogo extends CustomPainter {
  const PintorDoLogo({this.cheio = false, this.escala = 0.6});

  final bool cheio;
  final double escala;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final fundo = Paint()..color = fundoDaMarca;
    final quadrado = Offset.zero & size;
    if (cheio) {
      canvas.drawRect(quadrado, fundo);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(quadrado, Radius.circular(6 * u)),
        fundo,
      );
    }

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(escala);
    canvas.translate(-size.width / 2, -size.height / 2);

    RRect caixa(double l, double t, double r, double b, double raio) =>
        RRect.fromLTRBR(l * u, t * u, r * u, b * u, Radius.circular(raio * u));

    // O corpo da carteira, com o recorte onde entra o fecho.
    final corpo = Path.combine(
      PathOperation.difference,
      Path()..addRRect(caixa(3, 3, 21, 21, 2)),
      Path()..addRRect(caixa(10, 6, 22, 18, 2)),
    );
    // O fecho, com o botão vazado.
    final fecho = Path.combine(
      PathOperation.difference,
      Path()..addRRect(caixa(12, 8, 22, 16, 0.6)),
      Path()..addOval(Rect.fromCircle(center: Offset(16 * u, 12 * u), radius: 1.5 * u)),
    );
    final tinta = Paint()..color = corDaMarca;
    canvas.drawPath(corpo, tinta);
    canvas.drawPath(fecho, tinta);

    canvas.restore();
  }

  @override
  bool shouldRepaint(PintorDoLogo old) =>
      old.cheio != cheio || old.escala != escala;
}
