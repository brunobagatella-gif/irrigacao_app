import 'dart:math' as math;

import 'package:flutter/material.dart';

enum EstadoPlanta { murcha, saudavel, encharcada }

/// Feijoeiro no vaso, desenhado em código. Muda conforme o estado do solo.
class PlantaIlustracao extends StatelessWidget {
  final EstadoPlanta estado;
  final bool regando;
  final double largura;
  const PlantaIlustracao({super.key, required this.estado, this.regando = false, this.largura = 104});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: largura,
        height: largura * 120 / 104,
        child: CustomPaint(painter: _PlantaPainter(estado, regando)),
      );
}

class _PlantaPainter extends CustomPainter {
  final EstadoPlanta estado;
  final bool regando;
  _PlantaPainter(this.estado, this.regando);

  void _folha(Canvas c, Offset base, double angulo, double comp, Color cor) {
    c.save();
    c.translate(base.dx, base.dy);
    c.rotate(angulo);
    final p = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(comp * 0.45, -comp * 0.42, comp, 0)
      ..quadraticBezierTo(comp * 0.5, comp * 0.34, 0, 0)
      ..close();
    c.drawPath(p, Paint()..color = cor);
    c.drawLine(Offset(comp * 0.08, 0), Offset(comp * 0.85, 0),
        Paint()
          ..color = Colors.white.withAlpha(70)
          ..strokeWidth = 1.2);
    c.restore();
  }

  void _gota(Canvas c, Offset o, double r, Color cor) {
    final p = Path()
      ..moveTo(o.dx, o.dy - r * 1.8)
      ..quadraticBezierTo(o.dx + r * 1.1, o.dy - r * 0.2, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx - r * 1.1, o.dy - r * 0.2, o.dx, o.dy - r * 1.8)
      ..close();
    c.drawPath(p, Paint()..color = cor);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 104, size.height / 120);

    // sombra e vaso
    canvas.drawOval(const Rect.fromLTWH(18, 108, 68, 10), Paint()..color = const Color(0x1A000000));
    final vaso = Path()
      ..moveTo(22, 78)
      ..lineTo(82, 78)
      ..lineTo(75, 112)
      ..lineTo(29, 112)
      ..close();
    canvas.drawPath(vaso, Paint()..color = const Color(0xFFB5643C));
    canvas.drawRRect(RRect.fromLTRBR(18, 72, 86, 82, const Radius.circular(3)),
        Paint()..color = const Color(0xFFC9744A));

    // solo
    final corSolo = switch (estado) {
      EstadoPlanta.murcha => const Color(0xFF9C7A5B),
      EstadoPlanta.saudavel => const Color(0xFF5D4037),
      EstadoPlanta.encharcada => const Color(0xFF3E2723),
    };
    canvas.drawRRect(RRect.fromLTRBR(22, 72, 82, 77, const Radius.circular(3)), Paint()..color = corSolo);
    if (estado == EstadoPlanta.murcha) {
      final r = Paint()
        ..color = const Color(0xFF6D5039)
        ..strokeWidth = 0.9;
      canvas.drawLine(const Offset(34, 73), const Offset(38, 76), r);
      canvas.drawLine(const Offset(63, 73), const Offset(60, 76), r);
    }
    if (estado == EstadoPlanta.encharcada) {
      canvas.drawOval(const Rect.fromLTWH(26, 69, 52, 7), Paint()..color = const Color(0xCC4FC3F7));
    }

    // caule e folhas
    final murcha = estado == EstadoPlanta.murcha;
    final verde1 = switch (estado) {
      EstadoPlanta.murcha => const Color(0xFFC0B54A),
      EstadoPlanta.saudavel => const Color(0xFF6DB45A),
      EstadoPlanta.encharcada => const Color(0xFF4F8A55),
    };
    final verde2 = switch (estado) {
      EstadoPlanta.murcha => const Color(0xFFAFA843),
      EstadoPlanta.saudavel => const Color(0xFF5FA350),
      EstadoPlanta.encharcada => const Color(0xFF437A4A),
    };
    final caule = Path()..moveTo(52, 74);
    if (murcha) {
      caule.quadraticBezierTo(50, 52, 58, 38);
    } else {
      caule.quadraticBezierTo(53, 52, 50, 30);
    }
    canvas.drawPath(
        caule,
        Paint()
          ..color = murcha ? const Color(0xFF8D9A3A) : const Color(0xFF4E8A3A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round);

    if (murcha) {
      // folhas caídas
      _folha(canvas, const Offset(51, 58), math.pi * 0.78, 24, verde1);
      _folha(canvas, const Offset(52, 52), math.pi * 0.2, 26, verde2);
      _folha(canvas, const Offset(57, 40), math.pi * 0.62, 18, verde1);
      _folha(canvas, const Offset(58, 38), math.pi * 0.35, 18, verde2);
    } else {
      _folha(canvas, const Offset(51, 58), -math.pi * 0.86, 27, verde1);
      _folha(canvas, const Offset(51, 50), -math.pi * 0.2, 30, verde2);
      _folha(canvas, const Offset(50, 36), -math.pi * 0.72, 20, verde1);
      _folha(canvas, const Offset(50, 32), -math.pi * 0.3, 21, verde2);
      // florzinhas (fase de floração)
      final flor = Paint()..color = const Color(0xFFF4F1E1);
      final borda = Paint()
        ..color = const Color(0xFFC9C1A0)
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(const Offset(61, 62), 3.2, flor);
      canvas.drawCircle(const Offset(61, 62), 3.2, borda);
      canvas.drawCircle(const Offset(40, 46), 2.8, flor);
      canvas.drawCircle(const Offset(40, 46), 2.8, borda);
    }

    // gotas
    if (regando) {
      _gota(canvas, const Offset(84, 38), 4.5, const Color(0xFF4FC3F7));
      _gota(canvas, const Offset(92, 52), 3.5, const Color(0xFF81D4FA));
      _gota(canvas, const Offset(80, 58), 3, const Color(0xFF4FC3F7));
    } else if (estado == EstadoPlanta.saudavel) {
      _gota(canvas, const Offset(88, 46), 5, const Color(0xFF4FC3F7));
    } else if (estado == EstadoPlanta.murcha) {
      // sol forte
      canvas.drawCircle(const Offset(88, 22), 7, Paint()..color = const Color(0xFFFFB300));
      final raio = Paint()
        ..color = const Color(0xFFFFB300)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(Offset(88 + 10 * math.cos(a), 22 + 10 * math.sin(a)),
            Offset(88 + 13 * math.cos(a), 22 + 13 * math.sin(a)), raio);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlantaPainter old) => old.estado != estado || old.regando != regando;
}

/// Anel de progresso para o conforto hídrico (meta 90 %).
class AnelConforto extends StatelessWidget {
  final double? fracao;
  final double tamanho;
  const AnelConforto({super.key, required this.fracao, this.tamanho = 76});

  @override
  Widget build(BuildContext context) {
    final f = fracao;
    final cor = f == null
        ? Colors.grey
        : (f >= 0.9 ? const Color(0xFF2E7D32) : (f >= 0.75 ? const Color(0xFFF9A825) : const Color(0xFFD84315)));
    return SizedBox(
      width: tamanho,
      height: tamanho,
      child: CustomPaint(
        painter: _AnelPainter(f ?? 0, cor),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(f == null ? '--' : '${(f * 100).round()}%',
                style: TextStyle(fontSize: tamanho * 0.22, fontWeight: FontWeight.w800, color: cor)),
            Text('meta 90%', style: TextStyle(fontSize: tamanho * 0.1, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}

class _AnelPainter extends CustomPainter {
  final double f;
  final Color cor;
  _AnelPainter(this.f, this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final base = Paint()
      ..color = const Color(0xFFDCEFD3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * f.clamp(0, 1),
        false,
        Paint()
          ..color = cor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _AnelPainter old) => old.f != f || old.cor != cor;
}
