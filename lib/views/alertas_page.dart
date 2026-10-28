import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../controllers/formatos.dart';
import '../models/alerta.dart';
import 'widgets.dart';

class AlertasPage extends StatefulWidget {
  const AlertasPage({super.key});

  @override
  State<AlertasPage> createState() => _AlertasPageState();
}

class _AlertasPageState extends State<AlertasPage> {
  @override
  void initState() {
    super.initState();
    // ao abrir, tudo passa a contar como lido
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppController>().marcarAlertasLidos());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final lista = c.alertas;
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas')),
      body: lista.isEmpty
          ? const Vazio(icone: Icons.notifications_none, texto: 'Nenhum alerta no histórico carregado.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ItemAlerta(a: lista[i]),
            ),
    );
  }
}

class _ItemAlerta extends StatelessWidget {
  final Alerta a;
  const _ItemAlerta({required this.a});

  @override
  Widget build(BuildContext context) {
    final (cor, icone) = switch (a.tipo) {
      TipoAlerta.perigo => (const Color(0xFFC62828), Icons.error_outline),
      TipoAlerta.aviso => (const Color(0xFFEF6C00), Icons.warning_amber_rounded),
      TipoAlerta.info => (const Color(0xFF0277BD), Icons.info_outline),
    };
    final tt = Theme.of(context).textTheme;
    return Painel(
      padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: cor),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Icon(icone, color: cor)),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.titulo, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(a.detalhe, style: tt.bodySmall),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(fmtDataHora(a.momento), style: tt.labelSmall),
          ),
        ]),
      ),
    );
  }
}
