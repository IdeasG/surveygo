import 'package:surveygo/features/settings/data/models/user_model.dart';
import 'package:surveygo/services/http_provider.dart';

class UserService {
  final HttpProvider _http;

  UserService({HttpProvider? httpProvider})
      : _http = httpProvider ?? HttpProvider();

  Future<UserModel> fetchProfile() async {
    final result = await _http.get('/security/profile/movil');

    if (result is Map<String, dynamic> && result.containsKey('usuario')) {
      final usuario = result['usuario'] as Map<String, dynamic>;
      return UserModel.fromApi(usuario);
    }

    // Si no viene con la clave 'usuario', intentar mapear directamente
    if (result is Map<String, dynamic>) {
      return UserModel.fromApi(result);
    }

    throw Exception('Formato de respuesta inválido para /security/profile');
  }
}
