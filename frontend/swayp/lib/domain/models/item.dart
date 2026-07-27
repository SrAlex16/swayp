/// Ítem de catálogo, tal como lo devuelve `GET /domains/<code>/seed`
/// (src/api/routes/seed_routes.py). Sin carrusel de imágenes múltiples: el
/// backend solo expone un `image_url` por ítem — `item_images` de
/// docs/ARCHITECTURE.md sección 3.3 nunca se llegó a implementar.
class Item {
  const Item({
    required this.itemId,
    required this.title,
    required this.imageUrl,
    required this.externalUrl,
  });

  final int itemId;
  final String title;
  final String? imageUrl;
  final String? externalUrl;

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      itemId: json['item_id'] as int,
      title: json['title'] as String,
      imageUrl: json['image_url'] as String?,
      externalUrl: json['external_url'] as String?,
    );
  }
}
