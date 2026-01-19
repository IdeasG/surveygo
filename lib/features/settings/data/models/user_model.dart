class UserModel {
  final int id;
  final String name;
  final String email;
  final String role;
  final String profileImage;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.profileImage = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      profileImage: json['profile_image'] ?? '',
    );
  }

  // Nuevo: mapea el objeto 'usuario' del backend
  factory UserModel.fromApi(Map<String, dynamic> api) {
    final nombres = (api['c_nombres'] ?? '').toString().trim();
    final apePat = (api['c_ape_paterno'] ?? '').toString().trim();
    final apeMat = (api['c_ape_materno'] ?? '').toString().trim();
    final fullName = [nombres, apePat, apeMat]
        .where((p) => p.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final idRol = api['id_rol'];
    final roleText = idRol != null ? 'Rol $idRol' : '';

    return UserModel(
      id: api['id_usuario'] ?? 0,
      name: fullName,
      email: api['c_email'] ?? '',
      role: roleText,
      profileImage: '', // El backend no provee imagen
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'profile_image': profileImage,
    };
  }
}