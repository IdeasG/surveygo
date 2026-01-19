import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/theme/app_colors.dart';

class QrSetupPage extends StatefulWidget {
  const QrSetupPage({Key? key}) : super(key: key);

  @override
  State<QrSetupPage> createState() => _QrSetupPageState();
}

class _QrSetupPageState extends State<QrSetupPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _saved = false;
  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    print('[QrSetupPage] initState: inicializando escáner QR');
  }

  @override
  void dispose() {
    print(
        '[QrSetupPage] dispose: liberando recursos del escáner y controlador manual');
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig(Map<String, String> data) async {
    print('[QrSetupPage] _saveConfig: data=$data');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('config_ip', data['ip'] ?? '');
    await prefs.setString('config_id_sistema', data['id_sistema'] ?? '');
    await prefs.setString('config_id_cliente', data['id_cliente'] ?? '');
    print(
        '[QrSetupPage] _saveConfig: configuración guardada en SharedPreferences');

    if (mounted) {
      print('[QrSetupPage] _saveConfig: navegando a /login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada correctamente')),
      );
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      print('[QrSetupPage] _saveConfig: widget no montado, no se navega');
    }
  }

  Map<String, String>? _parseQrContent(String raw) {
    print('[QrSetupPage] _parseQrContent: raw="$raw"');
    try {
      // Intenta primero con JSON estándar
      final decoded = jsonDecode(raw);
      print('[QrSetupPage] _parseQrContent: JSON decode OK');
      if (decoded is Map<String, dynamic>) {
        final ip = decoded['ip']?.toString() ?? '';
        final idSistema = decoded['id_sistema']?.toString() ?? '';
        final idCliente = decoded['id_cliente']?.toString() ?? '';
        print(
            '[QrSetupPage] _parseQrContent(JSON): ip=$ip, id_sistema=$idSistema, id_cliente=$idCliente');
        if (ip.isNotEmpty && idSistema.isNotEmpty && idCliente.isNotEmpty) {
          return {'ip': ip, 'id_sistema': idSistema, 'id_cliente': idCliente};
        }
      }
    } catch (e) {
      print('[QrSetupPage] _parseQrContent: JSON decode falló: $e');
      // Si no es JSON estándar, intenta con el formato específico {ip: '...', id_sistema: '...', id_cliente: '...'}
      final regexIp = RegExp(r"ip:\s*'([^']*)'");
      final regexIdSistema = RegExp(r"id_sistema:\s*'([^']*)'");
      final regexIdCliente = RegExp(r"id_cliente:\s*'([^']*)'");

      final ipMatch = regexIp.firstMatch(raw);
      final idSistemaMatch = regexIdSistema.firstMatch(raw);
      final idClienteMatch = regexIdCliente.firstMatch(raw);

      final ip = ipMatch?.group(1) ?? '';
      final idSistema = idSistemaMatch?.group(1) ?? '';
      final idCliente = idClienteMatch?.group(1) ?? '';
      print(
          '[QrSetupPage] _parseQrContent(plain-object): ip=$ip, id_sistema=$idSistema, id_cliente=$idCliente');

      if (ip.isNotEmpty && idSistema.isNotEmpty && idCliente.isNotEmpty) {
        return {'ip': ip, 'id_sistema': idSistema, 'id_cliente': idCliente};
      }

      // Si no coincide con el formato específico, intenta con formato tipo query string
      final pairs = raw.split('&');
      final map = <String, String>{};
      for (final p in pairs) {
        final kv = p.split('=');
        if (kv.length == 2) {
          map[kv[0]] = kv[1];
        }
      }
      final ipQuery = map['ip'] ?? '';
      final idSistemaQuery = map['id_sistema'] ?? '';
      final idClienteQuery = map['id_cliente'] ?? '';
      print(
          '[QrSetupPage] _parseQrContent(query): ip=$ipQuery, id_sistema=$idSistemaQuery, id_cliente=$idClienteQuery');

      if (ipQuery.isNotEmpty &&
          idSistemaQuery.isNotEmpty &&
          idClienteQuery.isNotEmpty) {
        return {
          'ip': ipQuery,
          'id_sistema': idSistemaQuery,
          'id_cliente': idClienteQuery
        };
      }
    }

    print(
        '[QrSetupPage] _parseQrContent: contenido inválido, no se pudo parsear');
    return null;
  }

  void _onDetect(BarcodeCapture capture) async {
    print('[QrSetupPage] _onDetect: barcodes=${capture.barcodes.length}');
    if (_saved) {
      print('[QrSetupPage] _onDetect: ya guardado, ignorando detección');
      return;
    }
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue ?? '';
    print('[QrSetupPage] _onDetect: rawValue="$raw"');
    final parsed = _parseQrContent(raw);
    print('[QrSetupPage] _onDetect: parsed=$parsed');
    if (parsed != null) {
      _saved = true;
      print('[QrSetupPage] _onDetect: detención válida, deteniendo cámara...');
      await _controller.stop();
      print(
          '[QrSetupPage] _onDetect: cámara detenida, guardando configuración...');
      await _saveConfig(parsed);
    } else {
      print('[QrSetupPage] _onDetect: QR inválido, mostrando SnackBar');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('QR inválido. Se requiere ip, id_sistema e id_cliente')),
        );
      }
    }
  }

  Future<void> _saveManual() async {
    final text = _manualController.text.trim();
    print('[QrSetupPage] _saveManual: input="$text"');
    final parsed = _parseQrContent(text);
    print('[QrSetupPage] _saveManual: parsed=$parsed');
    if (parsed != null) {
      await _saveConfig(parsed);
    } else {
      print(
          '[QrSetupPage] _saveManual: contenido inválido, mostrando SnackBar');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Contenido inválido. Formato esperado JSON o query string')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar por QR'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: AppColors.buttonTextColor,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.primaryColor,
                      width: 3.0,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Coloca el código QR dentro del cuadro',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                const Text(
                  'Si el QR no funciona, pega el contenido aquí (JSON o ip=...&id_sistema=...&id_cliente=...)',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _manualController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        "{ip:'84.247.176.139:5004', id_sistema:'43', id_cliente:'95'}",
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _saveManual,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: AppColors.buttonTextColor,
                  ),
                  child: const Text('Guardar manualmente'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
