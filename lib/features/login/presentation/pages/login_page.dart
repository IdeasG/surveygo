import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/config/system_presets.dart';
import 'package:surveygo/core/navigation/home_navigation.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/login/data/models/login_model.dart';
import 'package:surveygo/features/login/data/models/login_response.dart';
import 'package:surveygo/features/login/presentation/widgets/login_form.dart';
import 'package:surveygo/services/http_provider.dart';
import 'package:surveygo/services/survey_sync_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final HttpProvider _httpProvider = HttpProvider();
  bool _isLoading = false;
  String _currentMunicipioName = 'Municipalidad de Chancay';
  String _currentMunicipioIcon = '🌊';
  String _currentIdCliente = '232';

  @override
  void initState() {
    super.initState();
    _loadCurrentSystem();
  }

  Future<void> _loadCurrentSystem() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = (prefs.getString('config_id_cliente') ?? '232').trim();
    final savedName = prefs.getString('config_municipio_nombre');

    String name = savedName ?? 'Municipalidad de Chancay';
    String icon = '🌊';

    for (final p in SystemPresets.presets) {
      if (p.idCliente == clientId) {
        name = p.nombre;
        icon = p.icon;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _currentIdCliente = clientId;
        _currentMunicipioName = name;
        _currentMunicipioIcon = icon;
      });
    }
  }

  void _showSystemSelectorBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Modo Municipalidad / GLGIS',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...SystemPresets.presets.map((p) {
                  final isSelected = _currentIdCliente == p.idCliente;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: isSelected
                          ? AppColors.primaryColor.withValues(alpha: 0.08)
                          : Colors.grey.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected ? AppColors.primaryColor : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      leading: Text(p.icon, style: const TextStyle(fontSize: 26)),
                      title: Text(
                        p.nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppColors.primaryColor : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        '${p.description}\nID: ${p.idCliente} | Sistema: ${p.idSistema}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: AppColors.primaryColor)
                          : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await SystemPresets.applyPreset(p);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('is_saas_mode', false);
                        if (!mounted) return;
                        _loadCurrentSystem();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Cambiado a modo GLGIS: ${p.nombre}'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Configuración Manual del Servidor'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.pushNamed(context, '/qr-setup');
                    _loadCurrentSystem();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openProjectQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProjectScannerModal(
        onProjectJoined: (projectName) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Conectado al proyecto: $projectName!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeNavigation()),
          );
        },
      ),
    );
  }

  Future<void> _handleLogin(LoginModel loginModel, bool rememberMe) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Intentar inicio de sesión en SurveyGo SaaS primero
      try {
        final saasRes = await _httpProvider.post(
          '/surveygo/api/auth/login',
          body: {
            'email': loginModel.usuario.trim(),
            'password': loginModel.clave,
          },
        );

        if (saasRes != null && saasRes['success'] == true) {
          final token = saasRes['token']?.toString() ?? '';
          final user = saasRes['user'] ?? {};
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
          await prefs.setString('username', user['fullName'] ?? loginModel.usuario);
          await prefs.setString('user_email', user['email'] ?? '');
          await prefs.setBool('is_saas_mode', true);
          await prefs.setBool('isLoggedIn', true);

          _httpProvider.updateHeaders({
            'Authorization': 'Bearer $token',
          });

          await SurveySyncService().syncSurveys();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('¡Bienvenido, ${user['fullName'] ?? 'Usuario'}!'),
                backgroundColor: Colors.green,
              ),
            );

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeNavigation()),
            );
          }
          return;
        }
      } catch (_) {
        // Continuar con autenticación municipal si falló SaaS
      }

      // 2. Intentar autenticación municipal GLGIS
      final response = await _httpProvider.post(
        '/movil/security/singin',
        body: loginModel.toJson(),
      );

      final loginResponse = LoginResponse.fromJson(response);

      if (loginResponse.isSuccess) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_saas_mode', false);

        _httpProvider.updateHeaders({
          'Authorization': 'Bearer ${loginResponse.token}',
        });

        await _saveSession(
          loginResponse.token,
          loginModel.usuario,
          loginResponse.idUsuario,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loginResponse.message)),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeNavigation()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${loginResponse.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar con el servidor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _enterDemoMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', 'demo_token');
    await prefs.setString('username', 'Encuestador Demo');
    await prefs.setInt('userId', 1);
    await prefs.setBool('isLoggedIn', true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresando en Modo Demostración / Offline'),
          backgroundColor: AppColors.primaryColor,
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeNavigation()),
      );
    }
  }

  Future<void> _saveSession(String token, String username, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    await prefs.setInt('userId', userId);
    await prefs.setBool('isLoggedIn', true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    AppColors.secondaryColor,
                  ],
                  stops: [0.7, 1.0],
                ),
              ),
            ),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryColor.withValues(alpha: 0.25),
                              blurRadius: 15,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Image.asset('assets/icon/app_icon.png'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SurveyGo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Plataforma de Encuestas Geoespaciales',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textColor,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // BOTÓN PRINCIPAL: ESCANEAR QR DE PROYECTO
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primaryColor, Color(0xFF1E3A8A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openProjectQrScanner,
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.white24,
                                  child: Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Escanear QR de Proyecto',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Ingreso instantáneo a brigadas sin contraseña',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'o inicia sesión con tu cuenta',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: LoginForm(onSubmit: _handleLogin),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Opciones Secundarias (Modo Demo & Modo Municipal)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.rocket_launch, size: 18),
                            label: const Text('Modo Demo', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _enterDemoMode,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Text(_currentMunicipioIcon, style: const TextStyle(fontSize: 16)),
                            label: Text(
                              _currentMunicipioName,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade800,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _showSystemSelectorBottomSheet,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    TextButton.icon(
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('Ajustes Avanzados del Servidor'),
                      onPressed: () => Navigator.pushNamed(context, '/qr-setup'),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectScannerModal extends StatefulWidget {
  final Function(String projectName) onProjectJoined;

  const _ProjectScannerModal({required this.onProjectJoined});

  @override
  State<_ProjectScannerModal> createState() => _ProjectScannerModalState();
}

class _ProjectScannerModalState extends State<_ProjectScannerModal> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _codeController = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _scannerController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _processProjectData(String raw) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final httpProvider = HttpProvider();

      String? token;
      String? projectId;
      String? projectName;
      String? code;

      final trimmed = raw.trim();
      if (trimmed.startsWith('{')) {
        final decoded = jsonDecode(trimmed);
        token = decoded['token']?.toString();
        projectId = decoded['project_id']?.toString();
        projectName = decoded['project_name']?.toString();
        code = decoded['project_code']?.toString();

        final apiUrl = decoded['api_url']?.toString();
        if (apiUrl != null && apiUrl.isNotEmpty) {
          final uri = Uri.tryParse(apiUrl);
          if (uri != null && uri.host.isNotEmpty) {
            await prefs.setString('config_ip', uri.host + (uri.hasPort ? ':${uri.port}' : ''));
          }
        }
      } else {
        code = trimmed.toUpperCase();
      }

      if ((token == null || token.isEmpty) && code != null && code.isNotEmpty) {
        final joinRes = await httpProvider.post(
          '/surveygo/api/projects/join',
          body: {'code': code},
        );

        if (joinRes != null && joinRes['success'] == true) {
          final proj = joinRes['project'];
          token = proj['token']?.toString();
          projectId = proj['id']?.toString();
          projectName = proj['name']?.toString();
        } else {
          throw Exception(joinRes?['error'] ?? 'Código de proyecto no reconocido');
        }
      }

      if (token != null && token.isNotEmpty) {
        await prefs.setString('token', token);
        await prefs.setString('username', projectName ?? 'Brigadista de Campo');
        await prefs.setString('project_id', projectId ?? '');
        await prefs.setBool('is_saas_mode', true);
        await prefs.setBool('isLoggedIn', true);

        httpProvider.updateHeaders({
          'Authorization': 'Bearer $token',
        });

        await SurveySyncService().syncSurveys();

        await _scannerController.stop();
        widget.onProjectJoined(projectName ?? 'Proyecto Activo');
      } else {
        throw Exception('No se pudo autenticar el proyecto');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Escanear QR de Proyecto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    final barcode = capture.barcodes.firstOrNull;
                    if (barcode?.rawValue != null) {
                      _processProjectData(barcode!.rawValue!);
                    }
                  },
                ),
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primaryColor, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Descargando formularios del proyecto...',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'O escribe código (Ej: PRJ-CHANCAY-2026)',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        if (_codeController.text.trim().isNotEmpty) {
                          _processProjectData(_codeController.text);
                        }
                      },
                      child: const Text('Unirse'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
