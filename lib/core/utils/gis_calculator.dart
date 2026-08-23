import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

enum GeoGeometryType {
  point,
  line,
  polygon,
}

class GisCalculator {
  static const double earthRadiusMeters = 6378137.0;

  /// Calcula la distancia total en metros entre una secuencia de coordenadas (Línea)
  static double calculateDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    const distance = Distance();
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }

  /// Calcula el perímetro de un polígono cerrado en metros
  static double calculatePerimeter(List<LatLng> points) {
    if (points.length < 3) return 0.0;
    final closedPoints = List<LatLng>.from(points);
    if (closedPoints.first != closedPoints.last) {
      closedPoints.add(closedPoints.first);
    }
    return calculateDistance(closedPoints);
  }

  /// Calcula el área esférica aproximada de un polígono en metros cuadrados
  static double calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0.0;

    double total = 0.0;
    final int len = points.length;

    for (int i = 0; i < len; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % len];

      final double radLat1 = _degToRad(p1.latitude);
      final double radLat2 = _degToRad(p2.latitude);
      final double radLng1 = _degToRad(p1.longitude);
      final double radLng2 = _degToRad(p2.longitude);

      total += (radLng2 - radLng1) * (2 + math.sin(radLat1) + math.sin(radLat2));
    }

    final area = (total * earthRadiusMeters * earthRadiusMeters / 2.0).abs();
    return area;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// Formatea la distancia a una cadena legible (m o km)
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(1)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }

  /// Formatea el área a una cadena legible (m², ha o km²)
  static String formatArea(double sqMeters) {
    if (sqMeters < 10000) {
      return '${sqMeters.toStringAsFixed(1)} m²';
    } else if (sqMeters < 1000000) {
      final hectares = sqMeters / 10000;
      return '${hectares.toStringAsFixed(2)} ha (${sqMeters.toStringAsFixed(0)} m²)';
    } else {
      final sqKm = sqMeters / 1000000;
      return '${sqKm.toStringAsFixed(2)} km²';
    }
  }

  /// Convierte una lista de puntos al formato GeoJSON estándar
  static Map<String, dynamic> toGeoJson(GeoGeometryType type, List<LatLng> points) {
    switch (type) {
      case GeoGeometryType.point:
        if (points.isEmpty) return {};
        return {
          "type": "Point",
          "coordinates": [points.first.longitude, points.first.latitude],
        };

      case GeoGeometryType.line:
        return {
          "type": "LineString",
          "coordinates": points.map((p) => [p.longitude, p.latitude]).toList(),
        };

      case GeoGeometryType.polygon:
        if (points.length < 3) return {};
        final coords = points.map((p) => [p.longitude, p.latitude]).toList();
        // Asegurar que el polígono esté cerrado
        if (coords.isNotEmpty &&
            (coords.first[0] != coords.last[0] || coords.first[1] != coords.last[1])) {
          coords.add([coords.first[0], coords.first[1]]);
        }
        return {
          "type": "Polygon",
          "coordinates": [coords],
        };
    }
  }

  /// Parsea una cadena (GeoJSON o "lat,lon") y retorna la lista de puntos y su tipo
  static ({GeoGeometryType type, List<LatLng> points})? fromGeoJsonOrString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final typeStr = decoded['type']?.toString().toUpperCase();
        final coords = decoded['coordinates'];

        if (typeStr == 'POINT' && coords is List && coords.length >= 2) {
          final lng = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();
          return (type: GeoGeometryType.point, points: [LatLng(lat, lng)]);
        }

        if (typeStr == 'LINESTRING' && coords is List) {
          final pts = <LatLng>[];
          for (var item in coords) {
            if (item is List && item.length >= 2) {
              pts.add(LatLng((item[1] as num).toDouble(), (item[0] as num).toDouble()));
            }
          }
          return (type: GeoGeometryType.line, points: pts);
        }

        if (typeStr == 'POLYGON' && coords is List && coords.isNotEmpty) {
          final ring = coords.first;
          if (ring is List) {
            final pts = <LatLng>[];
            for (var item in ring) {
              if (item is List && item.length >= 2) {
                pts.add(LatLng((item[1] as num).toDouble(), (item[0] as num).toDouble()));
              }
            }
            // Eliminar último punto repetido si viene cerrado
            if (pts.length > 3 && pts.first == pts.last) {
              pts.removeLast();
            }
            return (type: GeoGeometryType.polygon, points: pts);
          }
        }
      }
    } catch (_) {
      // Intenta parseo fallback de "lng,lat" o "lat,lng"
      if (trimmed.contains(',')) {
        final parts = trimmed.split(',');
        if (parts.length == 2) {
          final p0 = double.tryParse(parts[0].trim());
          final p1 = double.tryParse(parts[1].trim());
          if (p0 != null && p1 != null) {
            if (p0 >= -90 && p0 <= 90 && p1 >= -180 && p1 <= 180) {
              return (type: GeoGeometryType.point, points: [LatLng(p0, p1)]);
            } else {
              return (type: GeoGeometryType.point, points: [LatLng(p1, p0)]);
            }
          }
        }
      }
    }

    return null;
  }
}
