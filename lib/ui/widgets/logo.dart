import 'package:flutter/material.dart';

/// Laranja da marca. Fixo, e não o acento do tema: o logo é o mesmo em
/// qualquer tema, na aba do navegador e no ícone da tela inicial.
const corDaMarca = Color(0xFFFF9F1A);

/// Tinta escura do desenho sobre o laranja.
const tintaDaMarca = Color(0xFF1A1206);

/// Logo do ExtratoCripto: um extrato — papel com a borda de baixo serrilhada
/// e três linhas de texto — sobre o quadrado laranja.
class LogoExtratoCripto extends StatelessWidget {
  const LogoExtratoCripto({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: PintorDoLogo()),
    );
  }
}

/// Desenha o logo numa grade de 24 unidades, a mesma do SVG da landing.
///
/// [cheio] pinta o quadrado inteiro, sem cantos arredondados: é o que os
/// ícones "maskable" pedem, porque o sistema recorta a forma que quiser.
/// [escala] encolhe o desenho em volta do centro, para caber na área segura
/// desses ícones.
class PintorDoLogo extends CustomPainter {
  const PintorDoLogo({this.cheio = false, this.escala = 1});

  final bool cheio;
  final double escala;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final fundo = Paint()..color = corDaMarca;
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

    Offset p(double x, double y) => Offset(x * u, y * u);

    // O papel, com a borda de baixo em serra, e as linhas vazadas nele.
    final papel = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(p(6, 3).dx, p(6, 3).dy);
    for (final ponto in [
      p(18, 3),
      p(18, 21),
      p(16, 19.5),
      p(14, 21),
      p(12, 19.5),
      p(10, 21),
      p(8, 19.5),
      p(6, 21),
    ]) {
      papel.lineTo(ponto.dx, ponto.dy);
    }
    papel.close();
    for (final (x, y, largura) in [(9.0, 8.0, 6.0), (9.0, 11.5, 6.0), (9.0, 15.0, 4.0)]) {
      papel.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x * u, y * u, largura * u, 1.6 * u),
        Radius.circular(0.8 * u),
      ));
    }
    canvas.drawPath(papel, Paint()..color = tintaDaMarca);

    canvas.restore();
  }

  @override
  bool shouldRepaint(PintorDoLogo old) =>
      old.cheio != cheio || old.escala != escala;
}
