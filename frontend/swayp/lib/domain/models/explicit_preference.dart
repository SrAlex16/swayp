/// Preferencia declarada explícitamente por el usuario en su perfil, por
/// dominio (docs/ARCHITECTURE.md sección 9 — distinta de las señales
/// implícitas del swipe), tal como la devuelve
/// `GET/PUT /users/domains/<code>/preferences`
/// (src/api/routes/profile_routes.py).
class ExplicitPreference {
  const ExplicitPreference({required this.tag, required this.weight});

  final String tag;
  final double weight;

  factory ExplicitPreference.fromJson(Map<String, dynamic> json) {
    return ExplicitPreference(
      tag: json['tag'] as String,
      weight: (json['weight'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'tag': tag, 'weight': weight};
}
