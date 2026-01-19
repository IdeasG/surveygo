class LoginResponse {
  final String status;
  final String message;
  final int idUsuario;
  final int idRol;
  final String token;

  LoginResponse({
    required this.status,
    required this.message,
    required this.idUsuario,
    required this.idRol,
    required this.token,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      idUsuario: json['id_usuario'] ?? 0,
      idRol: json['id_rol'] ?? 0,
      token: json['token'] ?? '',
    );
  }

  bool get isSuccess => status == 'success';
}