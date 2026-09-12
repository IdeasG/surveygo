import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:surveygo/env.dart' as env;
import 'package:shared_preferences/shared_preferences.dart';

class HttpProvider {
  // Headers por defecto para las solicitudes
  final Map<String, String> _baseHeaders = {
    "Content-Type": "application/json",
  };

  HttpProvider();

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

      final clientId = (prefs.getString('config_id_cliente') ?? env.id_cliente).trim();
      if (clientId.isNotEmpty) {
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
      throw Exception('Configuración no encontrada. Escanee el QR o configure el servidor.');
    }

    Uri uri;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      uri = Uri.parse(raw);
    } else if (raw.contains(':') || RegExp(r'^\d+\.\d+\.\d+\.\d+').hasMatch(raw)) {
      // Dirección IP directa o puerto local sin SSL -> usar http
      uri = Uri.parse('http://$raw');
    } else {
      // Dominio estándar -> usar https
      uri = Uri.parse('https://$raw');
    }

    final url = uri.toString();
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

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Tiempo de espera agotado al conectar con el servidor ($uri).');
      });
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

      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Tiempo de espera agotado al conectar con el servidor ($uri).');
      });
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

      final response = await http
          .put(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Tiempo de espera agotado al conectar con el servidor ($uri).');
      });
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

      final response = await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Tiempo de espera agotado al conectar con el servidor ($uri).');
      });
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
