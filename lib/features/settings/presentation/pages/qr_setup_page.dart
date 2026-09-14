import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/env.dart' as env;

import 'package:surveygo/core/config/system_presets.dart';

class QrSetupPage extends StatefulWidget {
  const QrSetupPage({Key? key}) : super(key: key);

  @override
  State<QrSetupPage> createState() => _QrSetupPageState();
}

class _QrSetupPageState extends State<QrSetupPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MobileScannerController _controller = MobileScannerController();
  bool _saved = false;
  String _selectedClientId = '232';

  final TextEditingController _ipController = TextEditingController(text: env.ip);
  final TextEditingController _idSistemaController = TextEditingController(text: '52');
  final TextEditingController _idClienteController = TextEditingController(text: '232');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = (prefs.getString('config_id_cliente') ?? '232').trim();
    if (mounted) {
      setState(() {
        _selectedClientId = clientId;
        _ipController.text = prefs.getString('config_ip') ?? env.ip;
        _idSistemaController.text = prefs.getString('config_id_sistema') ?? '52';
        _idClienteController.text = clientId;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    _ipController.dispose();
    _idSistemaController.dispose();
    _idClienteController.dispose();
    super.dispose();
  }

  void _selectPreset(MunicipalityPreset preset) async {
    setState(() {
      _selectedClientId = preset.idCliente;
      _ipController.text = preset.ip;
      _idSistemaController.text = preset.idSistema;
      _idClienteController.text = preset.idCliente;
    });

    await SystemPresets.applyPreset(preset);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sistema seleccionado: ${preset.nombre}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveConfig(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('config_ip', data['ip'] ?? '');
    await prefs.setString('config_id_sistema', data['id_sistema'] ?? '');
    await prefs.setString('config_id_cliente', data['id_cliente'] ?? '');
    if (data['nombre'] != null) {
      await prefs.setString('config_municipio_nombre', data['nombre']!);
    } else {
      // Find matching preset
      for (final p in SystemPresets.presets) {
        if (p.idCliente == data['id_cliente']) {
          await prefs.setString('config_municipio_nombre', p.nombre);
          break;
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración guardada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _useDefaultConfig() async {
    // Default: Chancay
    final preset = SystemPresets.presets.first;
    await SystemPresets.applyPreset(preset);
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Map<String, String>? _parseQrContent(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final ip = decoded['ip']?.toString() ?? '';
        final idSistema = decoded['id_sistema']?.toString() ?? '';
        final idCliente = decoded['id_cliente']?.toString() ?? '';
        if (ip.isNotEmpty && idSistema.isNotEmpty && idCliente.isNotEmpty) {
          return {'ip': ip, 'id_sistema': idSistema, 'id_cliente': idCliente};
        }
      }
    } catch (_) {
      final regexIp = RegExp(r"ip:\s*'([^']*)'");
      final regexIdSistema = RegExp(r"id_sistema:\s*'([^']*)'");
      final regexIdCliente = RegExp(r"id_cliente:\s*'([^']*)'");

      final ipMatch = regexIp.firstMatch(raw);
      final idSistemaMatch = regexIdSistema.firstMatch(raw);
      final idClienteMatch = regexIdCliente.firstMatch(raw);

      final ip = ipMatch?.group(1) ?? '';
      final idSistema = idSistemaMatch?.group(1) ?? '';
      final idCliente = idClienteMatch?.group(1) ?? '';

      if (ip.isNotEmpty && idSistema.isNotEmpty && idCliente.isNotEmpty) {
        return {'ip': ip, 'id_sistema': idSistema, 'id_cliente': idCliente};
      }
    }
    return null;
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_saved) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue ?? '';
    final parsed = _parseQrContent(raw);
    if (parsed != null) {
      _saved = true;
      await _controller.stop();
      await _saveConfig(parsed);
    }
  }

  void _saveManualFields() {
    final ip = _ipController.text.trim();
    final idSistema = _idSistemaController.text.trim();
    final idCliente = _idClienteController.text.trim();

    if (ip.isEmpty || idSistema.isEmpty || idCliente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa la IP, ID de Sistema y ID de Cliente'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _saveConfig({
      'ip': ip,
      'id_sistema': idSistema,
      'id_cliente': idCliente,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Servidor'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _useDefaultConfig,
            child: const Text(
              'Usar Defecto / Saltar',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: 'Configuración Manual'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Escanear QR'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Formulario Manual (Fácil, directo y no se traba)
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '1. Seleccionar Entidad / Municipalidad (Rápido)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elige la municipalidad con la que deseas trabajar:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                ...SystemPresets.presets.map((preset) {
                  final isSelected = _selectedClientId == preset.idCliente;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => _selectPreset(preset),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryColor.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryColor
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(preset.icon, style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.nombre,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isSelected ? AppColors.primaryColor : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    preset.description,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID Cliente: ${preset.idCliente} | ID Sistema: ${preset.idSistema}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? AppColors.primaryColor : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: AppColors.primaryColor, size: 24),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 10),
                const Text(
                  '2. Parámetros Técnicos del Servidor (Avanzado)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Se autocompletan al elegir un municipio, o edítalos para servidores personalizados.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección IP / Dominio y Puerto',
                    hintText: '84.247.176.139:5004',
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _idSistemaController,
                  decoration: const InputDecoration(
                    labelText: 'ID de Sistema (Módulo GLGIS)',
                    hintText: '43',
                    prefixIcon: Icon(Icons.layers),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _idClienteController,
                  decoration: const InputDecoration(
                    labelText: 'ID de Cliente (Entidad / Municipalidad)',
                    hintText: '95',
                    prefixIcon: Icon(Icons.domain),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar Configuración e Ir al Login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _saveManualFields,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('Restablecer Valores Predeterminados'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _ipController.text = env.ip;
                      _idSistemaController.text = env.id_sistema.trim();
                      _idClienteController.text = env.id_cliente.trim();
                    });
                  },
                ),
              ],
            ),
          ),

          // 2. Cámara QR
          Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primaryColor, width: 3.0),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Positioned(
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Apunta al código QR del sistema',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
