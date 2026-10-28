import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import 'alertas_page.dart';
import 'config_page.dart';
import 'controle_page.dart';
import 'cultivo_page.dart';
import 'dashboard_page.dart';
import 'decisoes_page.dart';
import 'historico_page.dart';
import 'horta.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _aba = 0;

  static const _titulos = ['Minha Horta', 'Histórico', 'Cultivo', 'Decisões da IA', 'Controle'];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    final online = c.dispositivoOnline;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const CustomPaint(painter: FolhasPainter(), child: SizedBox.expand()),
        titleSpacing: 16,
        title: Row(children: [
          const LogoBroto(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_titulos[_aba],
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: verdeEscuro)),
              Text('Irrigação inteligente',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurface.withAlpha(150), fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Alertas',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AlertasPage())),
            icon: Badge(
              isLabelVisible: c.alertasNaoLidos > 0,
              label: Text('${c.alertasNaoLidos > 9 ? '9+' : c.alertasNaoLidos}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          Tooltip(
            message: online ? 'ESP32 online' : 'ESP32 sem dados recentes',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.circle, size: 12, color: online ? const Color(0xFF43A047) : cs.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ConfigPage())),
          ),
        ],
      ),
      body: IndexedStack(index: _aba, children: const [
        DashboardPage(),
        HistoricoPage(),
        CultivoPage(),
        DecisoesPage(),
        ControlePage(),
      ]),
      bottomNavigationBar: NavHorta(atual: _aba, onTap: (i) => setState(() => _aba = i)),
    );
  }
}
