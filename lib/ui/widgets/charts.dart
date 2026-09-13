import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/format.dart';

/// Uma fatia do gráfico de alocação.
class Slice {
  const Slice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// Rosca com a distribuição do patrimônio por moeda.
///
/// O anel é desenhado ao aparecer, girando do topo no sentido do relógio, e
/// refaz o traço sempre que a distribuição muda — trocar de mês ou de
/// categoria mostra o novo desenho sendo construído, em vez de trocar a
/// figura num piscar.
class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.size = 148,
    this.centerTop,
    this.centerBottom,
    this.destaque,
    this.detalhe,
  });

  final List<Slice> slices;
  final double size;
  final String? centerTop;
  final String? centerBottom;

  /// Fatia em destaque. Passe um de fora para a legenda destacar junto; sem
  /// ele o gráfico guarda o próprio.
  final ValueNotifier<int?>? destaque;

  /// Linha extra no centro da fatia destacada, como o valor em reais.
  final String Function(int indice)? detalhe;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  /// O anel desacelera no fim, como um traço que chega ao ponto de partida.
  late final Animation<double> _traco = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  /// O texto do meio entra depois, quando já há anel em volta dele.
  late final Animation<double> _centro = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1, curve: Curves.easeOut),
  );

  /// Identifica a distribuição atual: mudou, o desenho recomeça.
  static String _assinatura(List<Slice> slices) =>
      slices.map((s) => '${s.label}:${s.value}').join('|');

  final _destaqueInterno = ValueNotifier<int?>(null);
  ValueNotifier<int?> get _destaque => widget.destaque ?? _destaqueInterno;

  /// Entrada e saída do destaque: a fatia cresce e as outras apagam.
  late final AnimationController _foco = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Última fatia destacada, mantida enquanto o destaque se desfaz.
  int? _desenhada;

  @override
  void initState() {
    super.initState();
    _destaque.addListener(_aoMudarDestaque);
  }

  void _aoMudarDestaque() {
    final indice = _destaque.value;
    setState(() {
      if (indice != null) _desenhada = indice;
    });
    indice != null ? _foco.forward() : _foco.reverse();
  }

  @override
  void didUpdateWidget(DonutChart old) {
    super.didUpdateWidget(old);
    if (old.destaque != widget.destaque) {
      (old.destaque ?? _destaqueInterno).removeListener(_aoMudarDestaque);
      _destaque.addListener(_aoMudarDestaque);
    }
    if (_assinatura(old.slices) != _assinatura(widget.slices)) {
      _controller.forward(from: 0);
      // Em outro mês a fatia destacada pode nem existir.
      if ((_destaque.value ?? -1) >= widget.slices.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _destaque.value = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _destaque.removeListener(_aoMudarDestaque);
    _destaqueInterno.dispose();
    _foco.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// A fatia sob o ponteiro. Só o anel conta: o miolo é para ler.
  int? _fatiaEm(Offset local) {
    final total = widget.slices.fold<double>(0, (s, f) => s + f.value);
    if (total <= 0) return null;

    final raio = widget.size / 2;
    final traco = widget.size * 0.14;
    final d = local - Offset(raio, raio);
    if (d.distance < raio - traco * 1.4 || d.distance > raio + 6) return null;

    // Ângulo a partir do topo, no sentido do relógio, como o desenho.
    var angulo = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (angulo < 0) angulo += math.pi * 2;

    var acumulado = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      acumulado += widget.slices[i].value / total * math.pi * 2;
      if (angulo <= acumulado) return i;
    }
    return widget.slices.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.slices.fold<double>(0, (sum, s) => sum + s.value);
    // Quem pediu menos animação no sistema recebe o gráfico já pronto.
    final semAnimacao = MediaQuery.disableAnimationsOf(context);
    final indice = _destaque.value;
    final ativo = indice != null && indice < widget.slices.length && total > 0;

    final Widget miolo;
    if (ativo) {
      final fatia = widget.slices[indice];
      final detalhe = widget.detalhe?.call(indice);
      miolo = Column(
        key: ValueKey('fatia-$indice'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size * 0.56,
            child: Text(
              fatia.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall?.copyWith(color: fatia.color),
            ),
          ),
          const SizedBox(height: 2),
          // A porcentagem sobe de zero até o valor da fatia.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fatia.value / total),
            duration: semAnimacao
                ? Duration.zero
                : const Duration(milliseconds: 550),
            curve: Curves.easeOutCubic,
            builder: (context, parte, _) => Text(
              fmtPercent(parte),
              style: context.texts.titleMedium?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (detalhe != null)
            Text(detalhe, style: context.texts.bodySmall),
        ],
      );
    } else {
      miolo = Column(
        key: const ValueKey('resumo'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.centerTop != null)
            Text(widget.centerTop!, style: context.texts.labelSmall),
          if (widget.centerBottom != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.centerBottom!,
                style: context.texts.titleMedium?.copyWith(fontSize: 15),
              ),
            ),
        ],
      );
    }

    return MouseRegion(
      onHover: (evento) {
        final i = _fatiaEm(evento.localPosition);
        if (i != _destaque.value) _destaque.value = i;
      },
      onExit: (_) => _destaque.value = null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (toque) {
          final i = _fatiaEm(toque.localPosition);
          // O mouse já destacou ao passar: o clique mantém. No toque, tocar
          // de novo na mesma fatia volta ao resumo.
          _destaque.value = toque.kind == PointerDeviceKind.mouse
              ? i
              : (i == _destaque.value ? null : i);
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_controller, _foco]),
            builder: (context, child) => CustomPaint(
              painter: _DonutPainter(
                slices: total > 0 ? widget.slices : const [],
                emptyColor: context.tones.surfaceAlt,
                progress: semAnimacao ? 1 : _traco.value,
                destaque: _desenhada,
                foco: semAnimacao ? (ativo ? 1 : 0) : _foco.value,
              ),
              child: Opacity(
                opacity: semAnimacao ? 1 : _centro.value,
                child: child,
              ),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: semAnimacao
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                transitionBuilder: (filho, animacao) => FadeTransition(
                  opacity: animacao,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.85, end: 1.0).animate(animacao),
                    child: filho,
                  ),
                ),
                child: miolo,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.emptyColor,
    this.progress = 1,
    this.destaque,
    this.foco = 0,
  });

  final List<Slice> slices;
  final Color emptyColor;

  /// Fatia destacada e quanto do destaque já entrou, de 0 a 1.
  final int? destaque;
  final double foco;

  /// Quanto da volta já foi traçado, de 0 a 1.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // O trilho apagado aparece por baixo desde o primeiro quadro: sem ele o
    // cartão ficaria com um buraco enquanto o anel não fecha.
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      paint..color = emptyColor,
    );

    if (slices.isEmpty) return;

    final total = slices.fold<double>(0, (sum, s) => sum + s.value);
    final voltaFeita = math.pi * 2 * progress.clamp(0.0, 1.0);
    var start = -math.pi / 2;
    var percorrido = 0.0;
    const gap = 0.035;

    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final sweep = (slice.value / total) * math.pi * 2;
      if (sweep <= 0) continue;

      // O que sobra da volta já traçada para esta fatia.
      final disponivel = voltaFeita - percorrido;
      if (disponivel <= 0) break;

      final cheia = math.max(sweep - gap, 0.02);
      final drawn = math.min(cheia, disponivel);
      if (drawn > 0) {
        final emFoco = i == destaque;
        // As outras apagam para a destacada saltar aos olhos.
        final cor = destaque == null || emFoco
            ? slice.color
            : slice.color.withValues(alpha: 1 - 0.62 * foco);

        if (emFoco && foco > 0) {
          // Engrossa para fora, mantendo a borda de dentro no lugar.
          final extra = stroke * 0.32 * foco;
          canvas.drawArc(
            rect.inflate(extra / 2),
            start,
            drawn,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke + extra
              ..strokeCap = StrokeCap.butt
              ..color = cor,
          );
        } else {
          canvas.drawArc(rect, start, drawn, false, paint..color = cor);
        }
      }

      start += sweep;
      percorrido += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices ||
      old.emptyColor != emptyColor ||
      old.progress != progress ||
      old.destaque != destaque ||
      old.foco != foco;
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

    // A altura fica no lado de fora do LayoutBuilder de propósito: quem
    // pergunta a altura deste gráfico — o Row de cartões lado a lado no
    // computador, por exemplo — recebe a resposta sem precisar rodar o
    // cálculo de largura, que não pode ser executado especulativamente.
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cabem = constraints.maxWidth / math.max(values.length, 1);
          // Com muitos meses o gráfico rola na horizontal em vez de espremer.
          if (cabem >= _minBarWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(child: _bar(context, i, maior)),
              ],
            );
          }

          return ListView.builder(
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
          );
        },
      ),
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
