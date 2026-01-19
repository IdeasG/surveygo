import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:surveygo/env.dart' as env;
import 'package:shared_preferences/shared_preferences.dart';

class HttpProvider {
  // URL base para las solicitudes API
  final String _baseUrl;

  // Headers por defecto para las solicitudes
  // Headers por defecto (sin env.dart)
  final Map<String, String> _baseHeaders = {
    "Content-Type": "application/json",
  };

  // Constructor sin dependencia de env.dart
  HttpProvider() : _baseUrl = '';

  void updateHeaders(Map<String, String> newHeaders) {
    _baseHeaders.addAll(newHeaders);
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final headers = Map<String, String>.from(_baseHeaders);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final clientId = prefs.getString('config_id_cliente');
      if (clientId != null && clientId.isNotEmpty) {
        headers['x-id-cliente'] = clientId;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error al obtener headers: $e');
      }
    }

    return headers;
  }

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString('config_ip') ?? env.ip).trim();

    if (raw.isEmpty) {
      throw Exception('Configuración no encontrada. Escanee el QR primero.');
    }

    final uri = Uri.parse(raw.contains('://') ? raw : 'https://$raw');
    if (uri.host.isEmpty) {
      throw Exception('Configuración inválida: config_ip=$raw');
    }

    final normalized = uri.replace(scheme: 'https');
    final url = normalized.toString();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  // Método GET
  Future<dynamic> get(String endpoint,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final baseUrl = await _getBaseUrl();
      final uri =
          Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
      final headers = await _getAuthHeaders();

      if (kDebugMode) {
        print('GET Request: $uri');
      }

      final response = await http.get(uri, headers: headers);
      return _processResponse(response);
    } catch (e) {
      throw Exception('Error en solicitud GET: $e');
    }
  }

  // Método POST
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _getAuthHeaders();

      if (kDebugMode) {
        print('POST Request: $uri');
        print('Body: $body');
      }

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Error en solicitud POST: $e');
    }
  }

  // Método PUT
  Future<dynamic> put(String endpoint, {dynamic body}) async {
    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _getAuthHeaders();

      if (kDebugMode) {
        print('PUT Request: $uri');
        print('Body: $body');
      }

      final response = await http.put(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Error en solicitud PUT: $e');
    }
  }

  // Método DELETE
  Future<dynamic> delete(String endpoint) async {
    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _getAuthHeaders();

      if (kDebugMode) {
        print('DELETE Request: $uri');
      }

      final response = await http.delete(uri, headers: headers);
      return _processResponse(response);
    } catch (e) {
      throw Exception('Error en solicitud DELETE: $e');
    }
  }

  // Procesar respuesta y manejar códigos de estado
  dynamic _processResponse(http.Response response) {
    if (kDebugMode) {
      print('Status Code: ${response.statusCode}');
      print('Response: ${response.body}');
    }

    switch (response.statusCode) {
      case 200:
      case 201:
        return jsonDecode(response.body);
      case 400:
        throw Exception('Solicitud incorrecta: ${response.body}');
      case 401:
      case 403:
        throw Exception('No autorizado: ${response.body}');
      case 404:
        throw Exception('Recurso no encontrado: ${response.body}');
      case 500:
      default:
        throw Exception('Error del servidor: ${response.statusCode}');
    }
  }
}
