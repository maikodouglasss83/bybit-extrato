import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/widgets/charts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tamanho = 200.0;
  const slices = [
    Slice('Transporte', 75, Colors.blue),
    Slice('Saúde', 25, Colors.red),
  ];

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(
          body: Center(
            child: DonutChart(
              slices: slices,
              size: tamanho,
              centerTop: 'CATEGORIAS',
              centerBottom: '2',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Um ponto no meio do traço do anel.
  ///
  /// Transporte (75%) vai do topo até as 9 horas, e Saúde fecha a volta até o
  /// topo. Às 3 horas cai em cheio em Transporte; às 10h30, no meio de Saúde —
  /// longe das divisas, onde qualquer arredondamento trocaria a fatia.
  Offset noAnel(WidgetTester tester, {required bool direita}) {
    final centro = tester.getCenter(find.byType(DonutChart));
    const meioDoTraco = tamanho / 2 - tamanho * 0.07;
    if (direita) return centro + const Offset(meioDoTraco, 0);
    const diagonal = meioDoTraco * 0.7071;
    return centro + const Offset(-diagonal, -diagonal);
  }

  group('Rosca interativa', () {
    testWidgets('tocar numa fatia mostra a porcentagem dela', (tester) async {
      await montar(tester);
      expect(find.text('CATEGORIAS'), findsOneWidget);

      await tester.tapAt(noAnel(tester, direita: true));
      await tester.pumpAndSettle();

      expect(find.text('CATEGORIAS'), findsNothing);
      expect(find.text('Transporte'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);

      // Tocar de novo na mesma fatia volta ao resumo.
      await tester.tapAt(noAnel(tester, direita: true));
      await tester.pumpAndSettle();
      expect(find.text('CATEGORIAS'), findsOneWidget);
    });

    testWidgets('passar o mouse destaca e sair limpa', (tester) async {
      await montar(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(noAnel(tester, direita: false));
      await tester.pumpAndSettle();
      expect(find.text('Saúde'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text('CATEGORIAS'), findsOneWidget);
    });

    testWidgets('o miolo não destaca nada', (tester) async {
      await montar(tester);

      await tester.tapAt(tester.getCenter(find.byType(DonutChart)));
      await tester.pumpAndSettle();

      expect(find.text('CATEGORIAS'), findsOneWidget);
    });
  });
}
