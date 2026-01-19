import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/core/theme/app_colors.dart';
import 'package:surveygo/features/settings/data/models/user_model.dart';
import 'package:surveygo/features/settings/presentation/widgets/profile_section.dart';
import 'package:surveygo/features/settings/presentation/widgets/settings_section.dart';
import 'package:surveygo/services/database_helper.dart';
import 'package:surveygo/services/http_provider.dart';
import 'package:surveygo/services/survey_sync_service.dart';
import 'package:surveygo/services/user_service.dart';

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
      // Obtener todas las respuestas de la base de datos
      final db = await _dbHelper.database;

      // Consulta para obtener los response_set_id únicos
      final List<Map<String, dynamic>> uniqueResponseSets =
          await db.rawQuery('''
        SELECT DISTINCT response_set_id 
        FROM survey_responses 
        WHERE response_set_id IS NOT NULL
      ''');

      // Contar el número de conjuntos de respuestas únicos
      setState(() {
        _responseCount = uniqueResponseSets.length;
      });
    } catch (e) {
      debugPrint('Error loading response count: $e');
    }
  }

  Future<void> _syncData() async {
    setState(() {
      _isLoading = true;
    });

    final SurveySyncService syncService = SurveySyncService();
    final bool success = await syncService.syncSurveys();

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Datos sincronizados correctamente'
              : 'Error al sincronizar datos'),
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
      // Get all surveys
      final surveys = await _dbHelper.getSurveys();
      int successCount = 0;
      int errorCount = 0;

      for (var survey in surveys) {
        final responses =
            await _dbHelper.getResponsesBySurvey(survey.id.toString());

        if (responses.isNotEmpty) {
          // Group responses by survey
          Map<String, List<Map<String, dynamic>>> responsesBySurvey = {};

          for (var response in responses) {
            final surveyId = response['id_encuesta'];
            if (!responsesBySurvey.containsKey(surveyId)) {
              responsesBySurvey[surveyId] = [];
            }
            responsesBySurvey[surveyId]!.add(response);
          }

          // Send each group of responses
          for (var entry in responsesBySurvey.entries) {
            final result = await _sendSurveyResponses(entry.key, entry.value);
            if (result) {
              successCount++;
              // Delete sent responses from local DB
              await _dbHelper.deleteResponsesBySurvey(entry.key);
            } else {
              errorCount++;
            }
          }
        }
      }

      // Refresh response count
      await _loadResponseCount();

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorCount == 0
                  ? 'Todas las respuestas enviadas correctamente'
                  : 'Enviadas: $successCount, Errores: $errorCount',
            ),
            backgroundColor: errorCount == 0
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

  Future<bool> _sendSurveyResponses(
      String surveyId, List<Map<String, dynamic>> responses) async {
    try {
      // Agrupar respuestas por response_set_id
      Map<String, List<Map<String, dynamic>>> responseGroups = {};

      for (var response in responses) {
        final responseSetId = response['response_set_id'] ?? 'default';
        if (!responseGroups.containsKey(responseSetId)) {
          responseGroups[responseSetId] = [];
        }
        responseGroups[responseSetId]!.add(response);
      }

      // Enviar cada grupo de respuestas por separado
      bool allSuccessful = true;

      for (var entry in responseGroups.entries) {
        final responseSetId = entry.key;
        final groupResponses = entry.value;

        // Format responses according to API requirements
        List<Map<String, dynamic>> formattedResponses = [];

        for (var response in groupResponses) {
          String? respuesta = response['c_respuesta']?.toString();
          final tipo = response['c_tipo_pregunta']?.toString().toUpperCase();
          final nombreFile = response['c_nombre_file']?.toString();
          final extension = response['c_extension']?.toString();

          // Si es PHOTO o FILE, y c_respuesta apunta a una ruta de archivo -> convertir a Base64
          if ((tipo == 'PHOTO' || tipo == 'FILE' || tipo == 'SIGNATURE') &&
              respuesta != null &&
              respuesta.isNotEmpty) {
            try {
              final file = File(respuesta);
              if (await file.exists()) {
                final bytes = await file.readAsBytes();
                respuesta = base64Encode(bytes);
              }
            } catch (e) {
              debugPrint('No se pudo leer archivo para respuesta: $e');
            }
          }

          formattedResponses.add({
            'id_pregunta':
                int.tryParse(response['id_pregunta'].toString()) ?? 0,
            'c_tipo_pregunta': response['c_tipo_pregunta'],
            'c_respuesta': respuesta,
            'c_nombre_file': nombreFile,
            'c_extension': extension,
            'glgis': response['glgis'] != null
                ? _parseCoordinates(response['glgis'])
                : null,
          });
        }

        // Create request body
        final requestBody = {
          'respuesta': {
            'id_encuesta': int.tryParse(surveyId) ?? 0,
            'id_campo_geometria': null,
            'response_set_id': responseSetId
          },
          'respuestasPregunta': formattedResponses
        };

        // Send to API
        final result = await _httpProvider.post(
            '/encuestas/respuesta/insertarConPreguntas',
            body: requestBody);

        final success = result != null &&
            (result['status'] == 'success' || result['status'] == 'ok');

        if (!success) {
          allSuccessful = false;
        }
      }

      return allSuccessful;
    } catch (e) {
      debugPrint('Error sending survey responses: $e');
      return false;
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

dynamic _parseCoordinates(String coordinates) {
  try {
    // Intentar parsear como JSON
    final decoded = jsonDecode(coordinates);

    if (decoded is Map<String, dynamic>) {
      // Si ya es un GeoJSON válido, lo normalizamos
      if (decoded.containsKey('type') && decoded.containsKey('coordinates')) {
        final coords = decoded['coordinates'];
        if (coords is List) {
          // Convertir a lista de double
          return {
            "type": decoded["type"],
            "coordinates": coords.map((c) => (c as num).toDouble()).toList(),
          };
        }
      }
    }
  } catch (_) {
    // Si falla el jsonDecode, tratamos como "lat,lon"
    if (coordinates.contains(',')) {
      final parts = coordinates.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lon = double.tryParse(parts[1].trim());
        if (lat != null && lon != null) {
          return {
            "type": "Point",
            "coordinates": [lon, lat] // ⚠️ [longitud, latitud]
          };
        }
      }
    }
  }

  // Si no se puede parsear, devolvemos null
  return null;
}
