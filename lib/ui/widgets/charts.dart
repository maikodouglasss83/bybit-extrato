import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Uma fatia do gráfico de alocação.
class Slice {
  const Slice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// Rosca com a distribuição do patrimônio por moeda.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.size = 148,
    this.centerTop,
    this.centerBottom,
  });

  final List<Slice> slices;
  final double size;
  final String? centerTop;
  final String? centerBottom;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (sum, s) => sum + s.value);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          slices: total > 0 ? slices : const [],
          emptyColor: context.tones.surfaceAlt,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centerTop != null)
                Text(centerTop!, style: context.texts.labelSmall),
              if (centerBottom != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    centerBottom!,
                    style: context.texts.titleMedium?.copyWith(fontSize: 15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.emptyColor});

  final List<Slice> slices;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    if (slices.isEmpty) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = emptyColor);
      return;
    }

    final total = slices.fold<double>(0, (sum, s) => sum + s.value);
    var start = -math.pi / 2;
    const gap = 0.035;

    for (final slice in slices) {
      final sweep = (slice.value / total) * math.pi * 2;
      if (sweep <= 0) continue;
      final drawn = math.max(sweep - gap, 0.02);
      canvas.drawArc(rect, start, drawn, false, paint..color = slice.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.emptyColor != emptyColor;
}

/// Linha da evolução do saldo, com área preenchida abaixo.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.points,
    this.height = 96,
    this.color,
  });

  final List<double> points;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final line = color ?? AppColors.accent;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: points.length < 2
          ? Center(
              child: Text('Dados insuficientes', style: context.texts.bodySmall),
            )
          : CustomPaint(painter: _SparklinePainter(points: points, color: line)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final minV = points.reduce(math.min);
    final maxV = points.reduce(math.max);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    const padY = 8.0;

    Offset at(int i) {
      final x = size.width * (i / (points.length - 1));
      final norm = (points[i] - minV) / span;
      final y = size.height - padY - norm * (size.height - padY * 2);
      return Offset(x, y);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final prev = at(i - 1);
      final curr = at(i);
      final midX = (prev.dx + curr.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    final last = at(points.length - 1);
    canvas.drawCircle(last, 4.5, Paint()..color = color);
    canvas.drawCircle(
      last,
      8,
      Paint()..color = color.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.points != points || old.color != color;
}

/// Barras verticais para comparar meses. O mês mais recente vem destacado,
/// porque normalmente é o que ainda está em curso.
class MonthlyBars extends StatelessWidget {
  const MonthlyBars({
    super.key,
    required this.values,
    required this.labels,
    required this.valueLabel,
    this.height = 130,
  });

  final List<double> values;
  final List<String> labels;

  /// Texto do topo da barra, já formatado na moeda escolhida.
  final String Function(double) valueLabel;

  final double height;

  /// Abaixo disso a barra fica estreita demais para o valor caber em cima.
  static const _minBarWidth = 54.0;

  @override
  Widget build(BuildContext context) {
    final maior = values.isEmpty ? 0.0 : values.reduce(math.max);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cabem = constraints.maxWidth / math.max(values.length, 1);
        // Com muitos meses o gráfico rola na horizontal em vez de espremer.
        if (cabem >= _minBarWidth) {
          return SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(child: _bar(context, i, maior)),
              ],
            ),
          );
        }

        return SizedBox(
          height: height,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: values.length,
            itemBuilder: (context, index) {
              // Invertido para o mês mais recente já aparecer na abertura.
              final i = values.length - 1 - index;
              return SizedBox(
                width: _minBarWidth,
                child: _bar(context, i, maior),
              );
            },
          ),
        );
      },
    );
  }

  Widget _bar(BuildContext context, int i, double maior) {
    final tones = context.tones;
    return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        valueLabel(values[i]),
                        style: context.texts.bodySmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: i == values.length - 1
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: i == values.length - 1
                              ? AppColors.accent
                              : tones.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Altura proporcional, com um mínimo para o mês vazio
                    // ainda aparecer como uma marca no eixo.
                    Container(
                      height: maior <= 0
                          ? 4
                          : math.max(4, (values[i] / maior) * (height - 52)),
                      decoration: BoxDecoration(
                        color: i == values.length - 1
                            ? AppColors.accent
                            : AppColors.accent.withValues(alpha: 0.35),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                          bottom: Radius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[i],
                      style: context.texts.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
    );
  }
}

/// Barras horizontais comparando entradas e saídas.
class FlowBars extends StatelessWidget {
  const FlowBars({
    super.key,
    required this.inflow,
    required this.outflow,
    required this.inflowLabel,
    required this.outflowLabel,
  });

  final double inflow;
  final double outflow;
  final String inflowLabel;
  final String outflowLabel;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final peak = math.max(inflow.abs(), outflow.abs());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bar(context, 'Entradas', inflowLabel, peak == 0 ? 0 : inflow.abs() / peak, tones.positive),
        const SizedBox(height: 16),
        _bar(context, 'Saídas', outflowLabel, peak == 0 ? 0 : outflow.abs() / peak, tones.negative),
      ],
    );
  }

  Widget _bar(BuildContext context, String title, String value, double ratio, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: context.texts.bodySmall),
            Text(
              value,
              style: context.texts.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: context.tones.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
