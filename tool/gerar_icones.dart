// Gera os ícones do app a partir do mesmo desenho do logo usado nas telas.
//
// Uso: flutter test tool/gerar_icones.dart
//
// Roda como teste porque é onde o Flutter desenha em imagem sem abrir janela.
// Fica fora da pasta test/ de propósito: não é conferência, e não deve
// reescrever os arquivos a cada rodada da suíte.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bybit_extrato/ui/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('gera os ícones', (tester) async {
    // (arquivo, tamanho, cheio, escala)
    const icones = [
      ('web/icons/Icon-192.png', 192, false, 1.0),
      ('web/icons/Icon-512.png', 512, false, 1.0),
      // Maskable: o sistema recorta um círculo; o desenho fica na área segura.
      ('web/icons/Icon-maskable-192.png', 192, true, 0.78),
      ('web/icons/Icon-maskable-512.png', 512, true, 0.78),
      ('web/favicon.png', 64, false, 1.0),
    ];

    await tester.runAsync(() async {
      for (final (caminho, tamanho, cheio, escala) in icones) {
        final gravador = ui.PictureRecorder();
        PintorDoLogo(cheio: cheio, escala: escala).paint(
          Canvas(gravador),
          Size.square(tamanho.toDouble()),
        );
        final imagem =
            await gravador.endRecording().toImage(tamanho, tamanho);
        final png = await imagem.toByteData(format: ui.ImageByteFormat.png);
        File(caminho).writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
  });
}
