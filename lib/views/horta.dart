import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Elementos visuais com tema de horta: barra de navegação com grama,
/// logo de broto e folhas decorativas no cabeçalho.

const verdeEscuro = Color(0xFF1B5E20);
const verde = Color(0xFF2E7D32);
const verdeClaro = Color(0xFFDCEFD3);

/// Barra de navegação inferior com uma faixa de grama na borda de cima.
class NavHorta extends StatelessWidget {
  final int atual;
  final ValueChanged<int> onTap;
  const NavHorta({super.key, required this.atual, required this.onTap});

  static const itens = [
    (Icons.yard_outlined, Icons.yard, 'Início'),
    (Icons.grass_outlined, Icons.grass, 'Histórico'),
    (Icons.eco_outlined, Icons.eco, 'Decisões'),
    (Icons.water_drop_outlined, Icons.water_drop, 'Controle'),
  ];

  @override
  Widget build(BuildContext context) {
    final inferior = MediaQuery.of(context).padding.bottom;
    const grama = 16.0;
    return SizedBox(
      height: 76 + grama + inferior,
      child: Stack(children: [
        Positioned.fill(
          top: grama - 2,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFE4F2DC), Color(0xFFCDE5C0)],
              ),
            ),
          ),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: grama,
          child: CustomPaint(painter: GramaPainter()),
        ),
        Positioned(
          top: grama,
          left: 8,
          right: 8,
          bottom: inferior,
          child: Row(children: [
            for (var i = 0; i < itens.length; i++)
              Expanded(
                child: _ItemNav(
                  icone: itens[i].$1,
                  iconeAtivo: itens[i].$2,
                  texto: itens[i].$3,
                  ativo: i == atual,
                  onTap: () => onTap(i),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ItemNav extends StatelessWidget {
  final IconData icone, iconeAtivo;
  final String texto;
  final bool ativo;
  final VoidCallback onTap;
  const _ItemNav({
    required this.icone,
    required this.iconeAtivo,
    required this.texto,
    required this.ativo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: ativo,
      button: true,
      label: texto,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: ativo ? 58 : 44,
            height: 32,
            decoration: BoxDecoration(
              color: ativo ? verde : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: ativo
                  ? [BoxShadow(color: verde.withAlpha(70), blurRadius: 8, offset: const Offset(0, 3))]
                  : null,
            ),
            child: Icon(ativo ? iconeAtivo : icone,
                size: 22, color: ativo ? Colors.white : const Color(0xFF3E5A38)),
          ),
          const SizedBox(height: 4),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: ativo ? FontWeight.w800 : FontWeight.w500,
              color: ativo ? verdeEscuro : const Color(0xFF4A5E45),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Folhas de grama de alturas variadas, nascendo da borda de cima da barra.
class GramaPainter extends CustomPainter {
  const GramaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height;
    final tons = [const Color(0xFF7CB86A), const Color(0xFF5FA350), const Color(0xFF8FC77C)];
    var i = 0;
    for (double x = -2; x < size.width + 4; x += 5.5, i++) {
      // pseudoaleatório determinístico: o desenho não muda entre frames
      final r1 = (math.sin(i * 12.9898) * 43758.5453) % 1;
      final r2 = (math.sin(i * 78.233) * 12543.123) % 1;
      final alt = 5 + r1.abs() * (size.height - 5);
      final inclina = (r2 - 0.5) * 5;
      final p = Path()
        ..moveTo(x - 2.4, base)
        ..quadraticBezierTo(x - 0.6, base - alt * 0.55, x + inclina, base - alt)
        ..quadraticBezierTo(x + 1.0, base - alt * 0.45, x + 2.4, base)
        ..close();
      canvas.drawPath(p, Paint()..color = tons[i % tons.length]);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Logo redondo com broto, usado no cabeçalho.
class LogoBroto extends StatelessWidget {
  final double tamanho;
  const LogoBroto({super.key, this.tamanho = 36});

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho,
        height: tamanho,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF66BB6A), verdeEscuro],
          ),
        ),
        child: Icon(Icons.spa, color: Colors.white, size: tamanho * 0.56),
      );
}

/// Folhas desenhadas bem claras no canto direito do cabeçalho.
class FolhasPainter extends CustomPainter {
  const FolhasPainter();

  void _folha(Canvas c, Offset centro, double comp, double angulo, Color cor) {
    c.save();
    c.translate(centro.dx, centro.dy);
    c.rotate(angulo);
    final p = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(comp * 0.5, -comp * 0.32, comp, 0)
      ..quadraticBezierTo(comp * 0.5, comp * 0.32, 0, 0)
      ..close();
    c.drawPath(p, Paint()..color = cor);
    c.drawLine(Offset.zero, Offset(comp * 0.9, 0),
        Paint()
          ..color = Colors.white.withAlpha(60)
          ..strokeWidth = 1);
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    _folha(canvas, Offset(w - 150, h + 6), 54, -0.9, const Color(0x1A2E7D32));
    _folha(canvas, Offset(w - 110, h + 4), 64, -1.35, const Color(0x222E7D32));
    _folha(canvas, Offset(w - 30, h + 10), 70, -2.3, const Color(0x1A43A047));
    _folha(canvas, Offset(w - 70, -8), 46, 0.9, const Color(0x1466BB6A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
