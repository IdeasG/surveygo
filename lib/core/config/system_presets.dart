import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveygo/env.dart' as env;

class MunicipalityPreset {
  final String idCliente;
  final String idSistema;
  final String nombre;
  final String slug;
  final String ip;
  final String icon;
  final String description;

  const MunicipalityPreset({
    required this.idCliente,
    required this.idSistema,
    required this.nombre,
    required this.slug,
    required this.ip,
    required this.icon,
    required this.description,
  });
}

class SystemPresets {
  static const List<MunicipalityPreset> presets = [
    MunicipalityPreset(
      idCliente: '232',
      idSistema: '52',
      nombre: 'Municipalidad de Chancay',
      slug: 'huaral',
      ip: 'glgisclienteb.ideasg.org',
      icon: '🌊',
      description: 'Sistema de Catastro Urbano y Encuestas Chancay',
    ),
    MunicipalityPreset(
      idCliente: '226',
      idSistema: '48',
      nombre: 'Municipalidad de La Molina',
      slug: 'lamolina',
      ip: 'glgisclienteb.ideasg.org',
      icon: '🏛️',
      description: 'Sistema Catastral y Fiscalización Urbana',
    ),
    MunicipalityPreset(
      idCliente: '173',
      idSistema: '36',
      nombre: 'Municipalidad de Saño',
      slug: 'mdsano',
      ip: 'glgisclienteb.ideasg.org',
      icon: '🌄',
      description: 'Catastro y Seguridad Ciudadana Saño (Huancayo)',
    ),
  ];

  static Future<MunicipalityPreset?> getCurrentPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = (prefs.getString('config_id_cliente') ?? env.id_cliente).trim();
    for (final p in presets) {
      if (p.idCliente == clientId) {
        return p;
      }
    }
    return null;
  }

  static Future<String> getCurrentMunicipioName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('config_municipio_nombre');
    if (savedName != null && savedName.isNotEmpty) {
      return savedName;
    }
    final preset = await getCurrentPreset();
    return preset?.nombre ?? 'Municipalidad de Chancay';
  }

  static Future<void> applyPreset(MunicipalityPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('config_ip', preset.ip);
    await prefs.setString('config_id_sistema', preset.idSistema);
    await prefs.setString('config_id_cliente', preset.idCliente);
    await prefs.setString('config_municipio_nombre', preset.nombre);
    await prefs.setString('config_url_base', preset.slug);
  }
}
