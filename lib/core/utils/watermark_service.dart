import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WatermarkService {
  /// Incrusta una franja inferior táctica con metadatos GPS, fecha/hora y precisión.
  static Future<String> stampMetadataOnImage({
    required String imagePath,
    required double latitude,
    required double longitude,
    double? accuracy,
    DateTime? timestamp,
    String? title,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return imagePath;

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final width = image.width;
      final height = image.height;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );

      // 1. Dibujar la imagen original
      canvas.drawImage(image, Offset.zero, Paint());

      // 2. Franja inferior semitransparente táctica
      final bannerHeight = (height * 0.12).clamp(90.0, 240.0);
      final bannerRect = Rect.fromLTWH(
        0,
        height - bannerHeight,
        width.toDouble(),
        bannerHeight,
      );

      final bannerPaint = Paint()
        ..color = const Color(0xCC0A0E1A) // Dark semi-transparente
        ..style = PaintingStyle.fill;
      canvas.drawRect(bannerRect, bannerPaint);

      // Línea divisoria superior de acento cian / turquesa GIS
      final accentPaint = Paint()
        ..color = const Color(0xFF00B4D8)
        ..strokeWidth = (width * 0.0035).clamp(3.0, 7.0);
      canvas.drawLine(
        Offset(0, height - bannerHeight),
        Offset(width.toDouble(), height - bannerHeight),
        accentPaint,
      );

      // 3. Formatear textos
      final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp ?? DateTime.now());
      final coordsStr = 'LAT: ${latitude.toStringAsFixed(6)} | LON: ${longitude.toStringAsFixed(6)}';
      final accStr = accuracy != null ? ' | PRECISIÓN: ±${accuracy.toStringAsFixed(1)}m' : '';
      const appBrand = 'SURVEYGO GIS SECURE VERIFIED';

      final fontSizeMain = (bannerHeight * 0.22).clamp(13.0, 34.0);
      final fontSizeSub = (bannerHeight * 0.16).clamp(10.0, 26.0);

      // Header: Marca + Fecha / Hora
      final textPainterHeader = TextPainter(
        text: TextSpan(
          text: '$appBrand  •  $timeStr',
          style: TextStyle(
            color: const Color(0xFF00B4D8),
            fontSize: fontSizeSub,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: width - 40);

      textPainterHeader.paint(
        canvas,
        Offset(24, height - bannerHeight + (bannerHeight * 0.12)),
      );

      // Coordenadas GPS y Precisión en color blanco de alto contraste
      final textPainterCoords = TextPainter(
        text: TextSpan(
          text: '$coordsStr$accStr',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSizeMain,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: width - 40);

      textPainterCoords.paint(
        canvas,
        Offset(24, height - bannerHeight + (bannerHeight * 0.40)),
      );

      // Pregunta / Título del levantamiento
      if (title != null && title.isNotEmpty) {
        final textPainterTitle = TextPainter(
          text: TextSpan(
            text: title.length > 70 ? '${title.substring(0, 67)}...' : title,
            style: TextStyle(
              color: Colors.white70,
              fontSize: fontSizeSub,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout(maxWidth: width - 40);

        textPainterTitle.paint(
          canvas,
          Offset(24, height - bannerHeight + (bannerHeight * 0.70)),
        );
      }

      // 4. Exportar a PNG
      final picture = recorder.endRecording();
      final watermarkedImage = await picture.toImage(width, height);
      final byteData = await watermarkedImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return imagePath;

      final outputPath = imagePath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '_geo.png');
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      return outputPath;
    } catch (e) {
      debugPrint('Error en WatermarkService: $e');
      return imagePath; // Fallback
    }
  }
}
