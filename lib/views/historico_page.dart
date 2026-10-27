import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/formatos.dart';
import '../models/leitura.dart';
import 'widgets.dart';

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  int _horas = 24;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final dados = c.janela(Duration(hours: _horas));

    if (dados.length < 2) {
      return c.carregando
          ? const Carregando(texto: 'Carregando histórico...')
          : const Vazio(icone: Icons.show_chart, texto: 'Ainda não há histórico suficiente em /historico.');
    }

    final fim = dados.last.momento;
    double x(Leitura l) => l.momento.difference(fim).inSeconds / 3600.0; // horas (≤ 0)
    final pts = _reduzir(dados, 240);
    final irrig = dados.where((l) => l.irrigou).toList();
    final r = c.resumo(dados);
    final proj = _projecaoSolo(dados, fim);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Center(
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 6, label: Text('6 h')),
            ButtonSegment(value: 12, label: Text('12 h')),
            ButtonSegment(value: 24, label: Text('24 h')),
          ],
          selected: {_horas},
          onSelectionChanged: (s) => setState(() => _horas = s.first),
        ),
      ),
      const SizedBox(height: 12),
      Painel(
        child: Row(children: [
          _Mini('Água', fmtVolume(r.volumeMl)),
          _Mini('Irrigações', '${r.irrigacoes}'),
          _Mini('Bomba', '${fmtNum(r.segundos, 0)} s'),
          _Mini('Bloqueios', '${r.bloqueios}'),
        ]),
      ),
      const Secao('Umidade do solo'),
      _Grafico(
        horas: _horas,
        fim: fim,
        minY: 0,
        maxY: 100,
        unidade: '%',
        maxX: proj == null ? 0 : 6,
        faixa: (35.0, 62.0, const Color(0xFF2E7D32)),
        series: [
          _Serie('Solo', const Color(0xFF6D4C41), [for (final l in pts) FlSpot(x(l), l.solo)],
              pontos: {for (final l in irrig) x(l)}),
          if (proj != null)
            _Serie('Projeção 6 h', const Color(0xFF6D4C41), proj, tracejada: true),
        ],
      ),
      _Legenda(itens: [
        ('Faixa ideal', const Color(0xFF2E7D32)),
        ('Irrigação', const Color(0xFF0277BD)),
        if (proj != null) ('Projeção (tendência 4 h)', const Color(0xFF6D4C41)),
      ]),
      const Secao('Temperatura'),
      _Grafico(
        horas: _horas,
        fim: fim,
        unidade: '°C',
        series: [_Serie('Temperatura', const Color(0xFFEF6C00), [for (final l in pts) FlSpot(x(l), l.temp)])],
      ),
      const Secao('Umidade do ar'),
      _Grafico(
        horas: _horas,
        fim: fim,
        minY: 0,
        maxY: 100,
        unidade: '%',
        series: [_Serie('Ar', const Color(0xFF00838F), [for (final l in pts) FlSpot(x(l), l.ar)])],
      ),
      const Secao('Altura da planta'),
      _Grafico(
        horas: _horas,
        fim: fim,
        unidade: 'cm',
        series: [
          _Serie('Altura', const Color(0xFF558B2F),
              [for (final l in pts) if (l.altura != null) FlSpot(x(l), l.altura!)]),
        ],
      ),
    ]);
  }

  /// Média por blocos para não desenhar milhares de pontos (em teste o ESP32 envia a cada 30 s).
  List<Leitura> _reduzir(List<Leitura> d, int max) {
    if (d.length <= max) return d;
    final passo = (d.length / max).ceil();
    final sel = <Leitura>{
      for (var i = 0; i < d.length; i += passo) d[i],
      ...d.where((l) => l.irrigou), // irrigações nunca são descartadas
      d.last,
    }.toList()
      ..sort((a, b) => a.momento.compareTo(b.momento));
    return sel;
  }

  /// Regressão linear da umidade nas últimas 4 h, projetada 6 h à frente (relatório, 7.6).
  List<FlSpot>? _projecaoSolo(List<Leitura> d, DateTime fim) {
    final ini = fim.subtract(const Duration(hours: 4));
    final ult = d.where((l) => l.momento.isAfter(ini)).toList();
    if (ult.length < 6) return null;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final l in ult) {
      final xv = l.momento.difference(fim).inSeconds / 3600.0;
      sx += xv;
      sy += l.solo;
      sxx += xv * xv;
      sxy += xv * l.solo;
    }
    final n = ult.length.toDouble();
    final den = n * sxx - sx * sx;
    if (den.abs() < 1e-9) return null;
    final a = (n * sxy - sx * sy) / den;
    final y0 = d.last.solo;
    return [
      for (var h = 0.0; h <= 6.0001; h += 0.5) FlSpot(h, (y0 + a * h).clamp(0, 100).toDouble()),
    ];
  }
}

class _Serie {
  final String nome;
  final Color cor;
  final List<FlSpot> spots;
  final bool tracejada;
  final Set<double> pontos; // valores de x onde marcar um ponto (irrigações)
  _Serie(this.nome, this.cor, this.spots, {this.tracejada = false, this.pontos = const {}});
}

class _Grafico extends StatelessWidget {
  final int horas;
  final DateTime fim;
  final List<_Serie> series;
  final double? minY, maxY;
  final double maxX;
  final String unidade;
  final (double, double, Color)? faixa;
  const _Grafico({
    required this.horas,
    required this.fim,
    required this.series,
    required this.unidade,
    this.minY,
    this.maxY,
    this.maxX = 0,
    this.faixa,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final estilo = TextStyle(fontSize: 10, color: cs.onSurface.withAlpha(150));

    final todos = [for (final s in series) ...s.spots];
    if (todos.isEmpty) {
      return const Painel(child: SizedBox(height: 60, child: Center(child: Text('Sem dados'))));
    }
    var lo = minY ?? todos.map((e) => e.y).reduce(math.min);
    var hi = maxY ?? todos.map((e) => e.y).reduce(math.max);
    if (minY == null || maxY == null) {
      final pad = math.max(1.0, (hi - lo) * 0.15);
      lo = (lo - pad).floorToDouble();
      hi = (hi + pad).ceilToDouble();
    }

    return Painel(
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 4),
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minX: -horas.toDouble(),
            maxX: maxX,
            minY: lo,
            maxY: hi,
            clipData: const FlClipData.all(),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: (hi - lo) / 4,
              getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant, strokeWidth: 0.6),
            ),
            rangeAnnotations: faixa == null
                ? RangeAnnotations()
                : RangeAnnotations(horizontalRangeAnnotations: [
                    HorizontalRangeAnnotation(y1: faixa!.$1, y2: faixa!.$2, color: faixa!.$3.withAlpha(25)),
                  ]),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: (hi - lo) / 4,
                  getTitlesWidget: (v, meta) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(v.toStringAsFixed(0), style: estilo, textAlign: TextAlign.right),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: horas / 4,
                  getTitlesWidget: (v, meta) {
                    if (v == meta.min) return const SizedBox.shrink();
                    final t = fim.add(Duration(minutes: (v * 60).round()));
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(v.abs() < 0.01 ? 'agora' : fmtHora(t), style: estilo),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) {
                  final t = fim.add(Duration(minutes: (s.x * 60).round()));
                  return LineTooltipItem(
                    '${fmtHora(t)}\n${fmtNum(s.y)} $unidade',
                    const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              for (final s in series)
                LineChartBarData(
                  spots: s.spots,
                  isCurved: true,
                  curveSmoothness: 0.15,
                  preventCurveOverShooting: true,
                  color: s.cor.withAlpha(s.tracejada ? 140 : 255),
                  barWidth: s.tracejada ? 2 : 2.4,
                  dashArray: s.tracejada ? [6, 4] : null,
                  belowBarData: BarAreaData(show: !s.tracejada, color: s.cor.withAlpha(22)),
                  dotData: FlDotData(
                    show: s.pontos.isNotEmpty,
                    checkToShowDot: (spot, _) => _perto(spot.x, s.pontos),
                    getDotPainter: (spot, p, bar, i) => FlDotCirclePainter(
                      radius: 4,
                      color: const Color(0xFF0277BD),
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _perto(double x, Set<double> alvos) {
    for (final a in alvos) {
      if ((a - x).abs() < 0.0005) return true;
    }
    return false;
  }
}

class _Legenda extends StatelessWidget {
  final List<(String, Color)> itens;
  const _Legenda({required this.itens});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Wrap(spacing: 14, runSpacing: 4, children: [
          for (final (nome, cor) in itens)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(nome, style: Theme.of(context).textTheme.bodySmall),
            ]),
        ]),
      );
}

class _Mini extends StatelessWidget {
  final String titulo, valor;
  const _Mini(this.titulo, this.valor);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(children: [
        Text(valor, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(titulo, style: tt.bodySmall),
      ]),
    );
  }
}
