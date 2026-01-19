class LoginModel {
  final String usuario;
  final String clave;
  final String idSistema;

  LoginModel({
    required this.usuario,
    required this.clave,
    required this.idSistema,
  });

  Map<String, dynamic> toJson() {
    return {
      'usuario': usuario,
      'clave': clave,
      'id_sistema': idSistema,
    };
  }

  factory LoginModel.fromJson(Map<String, dynamic> json) {
    return LoginModel(
      usuario: json['usuario'] ?? '',
      clave: json['clave'] ?? '',
      idSistema: json['id_sistema'] ?? '',
    );
  }
}