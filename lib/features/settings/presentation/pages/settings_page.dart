import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/settings/data/models/user_model.dart';
import 'package:surveygo/features/settings/presentation/widgets/profile_section.dart';
import 'package:surveygo/features/settings/presentation/widgets/settings_section.dart';
import 'package:file_picker/file_picker.dart';
import 'package:surveygo/core/utils/mbtiles_service.dart';
import 'package:surveygo/services/database_helper.dart';
import 'package:surveygo/services/http_provider.dart';
import 'package:surveygo/services/survey_sync_service.dart';
import 'package:surveygo/services/user_service.dart';
import 'package:surveygo/core/config/system_presets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = false;
  late UserModel _user;
  int _responseCount = 0;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final HttpProvider _httpProvider = HttpProvider();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadResponseCount();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('user_profile');

      if (cached != null && cached.isNotEmpty) {
        final Map<String, dynamic> jsonMap = jsonDecode(cached);
        final cachedUser = UserModel.fromJson(jsonMap);
        setState(() {
          _user = cachedUser;
          _isLoading = false;
        });
        return;
      }

      final userService = UserService(httpProvider: _httpProvider);
      final profile = await userService.fetchProfile();

      await prefs.setString('user_profile', jsonEncode(profile.toJson()));

      setState(() {
        _user = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _user = UserModel(
          id: 0,
          name: 'Usuario',
          email: '',
          role: '',
        );
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cargar el perfil: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _loadResponseCount() async {
    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> uniqueResponseSets = await db.rawQuery('''
        SELECT DISTINCT response_set_id 
        FROM survey_responses 
        WHERE response_set_id IS NOT NULL 
          AND COALESCE(status, 'COMPLETED') = 'COMPLETED'
      ''');

      setState(() {
        _responseCount = uniqueResponseSets.length;
      });
    } catch (e) {
      debugPrint('Error al cargar el contador de respuestas: $e');
    }
  }

  Future<void> _syncData() async {
    setState(() {
      _isLoading = true;
    });

    final SurveySyncService syncService = SurveySyncService();
    final bool success = await syncService.syncSurveys();
    final surveys = success ? await syncService.getLocalSurveys() : [];

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      final String msg = success
          ? (surveys.isNotEmpty
              ? 'Se sincronizaron ${surveys.length} formulario(s) con éxito'
              : 'Sincronizado: No hay encuestas asignadas a su rol')
          : 'Error al conectar con el servidor para sincronizar';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              success ? AppColors.successColor : AppColors.errorColor,
        ),
      );
    }
  }

  Future<void> _sendResponsesToServer() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final res = await SurveySyncService().sendAllCompletedResponses();
      await _loadResponseCount();

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: res.errorCount == 0
                ? AppColors.successColor
                : AppColors.warningColor,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar respuestas: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileSection(user: _user),
                  const SizedBox(height: 24),
                  SettingsSection(
                    title: 'Sincronización',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.sync,
                            color: AppColors.primaryColor),
                        title: const Text('Sincronizar datos'),
                        subtitle:
                            const Text('Actualizar datos con el servidor'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: _syncData,
                      ),
                      ListTile(
                        leading: const Icon(Icons.upload,
                            color: AppColors.primaryColor),
                        title: const Text('Enviar datos'),
                        subtitle: Text(
                            'Enviar $_responseCount respuestas al servidor'),
                        trailing: _responseCount > 0
                            ? Badge(
                                label: Text('$_responseCount'),
                                backgroundColor: AppColors.accentColor,
                              )
                            : const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap:
                            _responseCount > 0 ? _sendResponsesToServer : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsSection(
                    title: 'Mapas Base Offline (MBTiles)',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.map_outlined,
                            color: AppColors.primaryColor),
                        title: const Text('Capa Satelital / Vectorial Local'),
                        subtitle: Text(
                          MbtilesService().isMbtilesAvailable
                              ? 'Cargado: ${MbtilesService().layerName}\n(${MbtilesService().loadedFilePath})'
                              : 'Ningún archivo .mbtiles cargado actualmente',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (MbtilesService().isMbtilesAvailable)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Quitar MBTiles',
                                onPressed: () async {
                                  await MbtilesService().close();
                                  setState(() {});
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.folder_open, color: AppColors.primaryColor),
                              tooltip: 'Seleccionar archivo .mbtiles',
                              onPressed: () async {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['mbtiles', 'sqlite', 'db'],
                                );
                                if (result != null && result.files.single.path != null) {
                                  final ok = await MbtilesService().loadMbtiles(result.files.single.path!);
                                  if (mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(ok ? 'Mapa MBTiles cargado correctamente' : 'Error al leer el archivo MBTiles'),
                                        backgroundColor: ok ? AppColors.successColor : AppColors.errorColor,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsSection(
                    title: 'Sistema y Entidad Municipal',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.domain, color: AppColors.primaryColor),
                        title: const Text('Cambiar Entidad / Servidor'),
                        subtitle: FutureBuilder<String>(
                          future: SystemPresets.getCurrentMunicipioName(),
                          builder: (context, snapshot) {
                            return Text(snapshot.data ?? 'Configuración del Servidor');
                          },
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () async {
                          await Navigator.pushNamed(context, '/qr-setup');
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsSection(
                    title: 'Cuenta',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.logout,
                            color: AppColors.errorColor),
                        title: const Text('Cerrar sesión'),
                        onTap: _logout,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('token');
    await prefs.remove('username');
    await prefs.remove('userId');
    await prefs.remove('isLoggedIn');
    await prefs.remove('user_profile');

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }
}
