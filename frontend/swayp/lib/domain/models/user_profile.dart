/// Perfil de usuario (docs/ARCHITECTURE.md sección 7.2), tal como lo
/// devuelve `GET/PUT /users/profile` (src/api/routes/profile_routes.py). Un
/// perfil vacío es `200` con ambos campos en `null`, no un error.
class UserProfile {
  const UserProfile({required this.age, required this.gender});

  final int? age;
  final String? gender;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(age: json['age'] as int?, gender: json['gender'] as String?);
  }
}
