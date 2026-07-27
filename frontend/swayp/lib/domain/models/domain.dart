/// Dominio de recomendación (videojuegos, películas...), tal como lo
/// devuelve `GET /api/v1/domains` (docs/ARCHITECTURE.md sección 3.4).
class Domain {
  const Domain({required this.code, required this.displayName});

  final String code;
  final String displayName;

  factory Domain.fromJson(Map<String, dynamic> json) {
    return Domain(
      code: json['code'] as String,
      displayName: json['display_name'] as String,
    );
  }
}
