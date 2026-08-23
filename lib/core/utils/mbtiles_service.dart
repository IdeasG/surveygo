import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class MbtilesService {
  static final MbtilesService _instance = MbtilesService._internal();
  factory MbtilesService() => _instance;
  MbtilesService._internal();

  Database? _db;
  String? _loadedFilePath;
  String? _layerName;
  bool _isMbtilesAvailable = false;

  bool get isMbtilesAvailable => _isMbtilesAvailable;
  String? get loadedFilePath => _loadedFilePath;
  String? get layerName => _layerName;

  /// Inicializa cargando la última ruta configurada si existe
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('custom_mbtiles_path');
      if (savedPath != null && savedPath.isNotEmpty) {
        await loadMbtiles(savedPath);
      }
    } catch (e) {
      debugPrint('Error inicializando MBTiles: $e');
    }
  }

  /// Carga un archivo MBTiles por ruta
  Future<bool> loadMbtiles(String filePath) async {
    try {
      if (_db != null) {
        await _db!.close();
        _db = null;
      }

      _db = await openDatabase(filePath, readOnly: true);

      // Leer metadata
      try {
        final metadata = await _db!.query('metadata');
        for (var row in metadata) {
          if (row['name'] == 'name') {
            _layerName = row['value']?.toString();
          }
        }
      } catch (_) {}

      _loadedFilePath = filePath;
      _layerName ??= filePath.split(RegExp(r'[/\\]')).last;
      _isMbtilesAvailable = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_mbtiles_path', filePath);

      return true;
    } catch (e) {
      debugPrint('Error al abrir MBTiles: $e');
      _isMbtilesAvailable = false;
      return false;
    }
  }

  /// Obtiene los bytes de un tile (x, y, z) en formato TMS
  Future<Uint8List?> getTileBytes(int x, int y, int z) async {
    if (_db == null || !_isMbtilesAvailable) return null;

    try {
      // Conversión de XYZ a TMS: tms_y = 2^z - 1 - y
      final tmsY = (math.pow(2, z) - 1 - y).toInt();

      final results = await _db!.query(
        'tiles',
        columns: ['tile_data'],
        where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
        whereArgs: [z, x, tmsY],
        limit: 1,
      );

      if (results.isNotEmpty && results.first['tile_data'] != null) {
        return results.first['tile_data'] as Uint8List;
      }
    } catch (e) {
      debugPrint('Error consultando tile MBTiles: $e');
    }
    return null;
  }

  /// Cierra la base de datos de MBTiles
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _isMbtilesAvailable = false;
    _loadedFilePath = null;
    _layerName = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_mbtiles_path');
  }
}

/// Custom TileProvider para renderizar tiles desde MBTiles local
class MbtilesTileProvider extends TileProvider {
  final MbtilesService service = MbtilesService();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _MbtilesImageProvider(
      x: coordinates.x,
      y: coordinates.y,
      z: coordinates.z,
      service: service,
    );
  }
}

class _MbtilesImageProvider extends ImageProvider<_MbtilesImageKey> {
  final int x;
  final int y;
  final int z;
  final MbtilesService service;

  _MbtilesImageProvider({
    required this.x,
    required this.y,
    required this.z,
    required this.service,
  });

  @override
  Future<_MbtilesImageKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_MbtilesImageKey>(_MbtilesImageKey(x: x, y: y, z: z));
  }

  @override
  ImageStreamCompleter loadImage(_MbtilesImageKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty('Tile Coordinates', '${key.z}/${key.x}/${key.y}'),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(_MbtilesImageKey key, ImageDecoderCallback decode) async {
    final bytes = await service.getTileBytes(key.x, key.y, key.z);
    if (bytes != null && bytes.isNotEmpty) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    }
    // Retornar tile transparente si no existe en el mbtiles
    final transparent1px = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);
    final buffer = await ui.ImmutableBuffer.fromUint8List(transparent1px);
    return decode(buffer);
  }
}

class _MbtilesImageKey {
  final int x;
  final int y;
  final int z;

  _MbtilesImageKey({required this.x, required this.y, required this.z});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MbtilesImageKey &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => x.hashCode ^ y.hashCode ^ z.hashCode;
}
