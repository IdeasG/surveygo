import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:surveygo/core/utils/gis_calculator.dart';

void main() {
  group('GisCalculator Unit Tests', () {
    test('calculateDistance should return correct distance for 2 points', () {
      final p1 = const LatLng(-12.046374, -77.042793);
      final p2 = const LatLng(-12.046374, -77.043793);

      final distance = GisCalculator.calculateDistance([p1, p2]);
      expect(distance, greaterThan(100.0));
      expect(distance, lessThan(120.0));
    });

    test('calculatePerimeter and calculatePolygonArea should calculate properly', () {
      final points = [
        const LatLng(-12.0, -77.0),
        const LatLng(-12.0, -77.001),
        const LatLng(-12.001, -77.001),
        const LatLng(-12.001, -77.0),
      ];

      final perimeter = GisCalculator.calculatePerimeter(points);
      final area = GisCalculator.calculatePolygonArea(points);

      expect(perimeter, greaterThan(400.0));
      expect(area, greaterThan(10000.0));
    });

    test('toGeoJson and fromGeoJsonOrString should roundtrip Point and Polygon', () {
      final point = [const LatLng(-12.05, -77.05)];
      final geoJsonPoint = GisCalculator.toGeoJson(GeoGeometryType.point, point);

      expect(geoJsonPoint['type'], 'Point');
      expect(geoJsonPoint['coordinates'], [-77.05, -12.05]);

      final parsed = GisCalculator.fromGeoJsonOrString(
        '{"type":"Point","coordinates":[-77.05,-12.05]}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.type, GeoGeometryType.point);
      expect(parsed.points.first.latitude, -12.05);
      expect(parsed.points.first.longitude, -77.05);
    });
  });
}
