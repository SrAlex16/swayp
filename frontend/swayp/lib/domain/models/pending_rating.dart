/// Rating `interested` pendiente de confirmar (docs/ARCHITECTURE.md sección
/// 8.3), tal como lo devuelve `GET /domains/<code>/pending-confirmation`
/// (src/api/routes/ratings_routes.py).
class PendingRating {
  const PendingRating({
    required this.ratingId,
    required this.itemId,
    required this.title,
    required this.imageUrl,
    required this.externalUrl,
    required this.status,
    required this.createdAt,
  });

  final int ratingId;
  final int itemId;
  final String title;
  final String? imageUrl;
  final String? externalUrl;
  final String status;
  final String createdAt;

  factory PendingRating.fromJson(Map<String, dynamic> json) {
    return PendingRating(
      ratingId: json['rating_id'] as int,
      itemId: json['item_id'] as int,
      title: json['title'] as String,
      imageUrl: json['image_url'] as String?,
      externalUrl: json['external_url'] as String?,
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}
