// lib/screens/anime_recommendations_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AnimeRecommendationsScreen extends StatefulWidget {
  final List<dynamic> recommendations;
  final Map<String, dynamic> statistics;
  final String Function(String) tr;

  const AnimeRecommendationsScreen({
    super.key,
    this.recommendations = const [],
    this.statistics = const {},
    required this.tr,
  });

  @override
  State<AnimeRecommendationsScreen> createState() => _AnimeRecommendationsScreenState();
}

class _AnimeRecommendationsScreenState extends State<AnimeRecommendationsScreen>
    with SingleTickerProviderStateMixin {
  final Set<int> _selectedRecIds = {};
  late List<dynamic> _recommendations;

  late AnimationController _animationController;
  late Animation<double> _iconScaleAnimation;

  @override
  void initState() {
    super.initState();
    _recommendations = List.from(widget.recommendations);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _iconScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_recommendations.isNotEmpty) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is List) {
      _recommendations = List.from(args);
    } else if (args is Map) {
      final recs = args['recommendations'];
      if (recs is List) _recommendations = List.from(recs);
    }
    if (_recommendations.isNotEmpty) setState(() {});
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _cleanDescription(String htmlString) {
    String text = htmlString.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');
    return text.replaceAll(RegExp(r'\n+'), '\n').trim();
  }

  String _formatList(List<dynamic>? list) {
    if (list == null || list.isEmpty) return 'N/A';
    final effectiveList = list.take(3).toList();
    return effectiveList.join(', ');
  }

  void _toggleSelection(int malId) {
    setState(() {
      if (_selectedRecIds.contains(malId)) {
        _selectedRecIds.remove(malId);
        _animationController.reverse();
      } else {
        _selectedRecIds.add(malId);
        _animationController.forward(from: 0.0);
      }
    });
  }

  Future<void> _addToBlacklist() async {
    if (_selectedRecIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.tr('recommendations_error_no_selection'))),
      );
      return;
    }

    // 🔥 CRÍTICO: Usar MAL_ID en lugar de id
    final malIds = _selectedRecIds.toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(widget.tr('recommendations_blacklist_loading')),
          ],
        ),
      ),
    );

    try {
      final result = await ApiService.addToBlacklist(malIds);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();

      if (result['status'] == 'success') {
        setState(() {
          // 🔥 Eliminar usando MAL_ID
          _recommendations.removeWhere((rec) {
            final Map<String, dynamic> recMap = rec as Map<String, dynamic>;
            final malId = recMap['MAL_ID'] as int?;
            return _selectedRecIds.contains(malId);
          });
          _selectedRecIds.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.tr('recommendations_blacklist_success')} ${malIds.length}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(result['message'] ?? widget.tr('recommendations_blacklist_error_default'));
      }
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.tr('recommendations_blacklist_error')} $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4C5E87),
      appBar: AppBar(
        title: Text(widget.tr('recommendations_screen_title'),
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF4C5E87),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.block,
                color: _selectedRecIds.isNotEmpty
                    ? Colors.redAccent
                    : Colors.white54),
            onPressed: _addToBlacklist,
            tooltip: widget.tr('recommendations_blacklist_tooltip'),
          ),
        ],
      ),
      body: _recommendations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  widget.tr('recommendations_none_found'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 10.0),
              itemCount: _recommendations.length,
              itemBuilder: (context, index) {
                final Map<String, dynamic> rec =
                    _recommendations[index] as Map<String, dynamic>;
                
                // 🔥 CRÍTICO: Usar MAL_ID consistentemente
                final int malId = rec['MAL_ID'] as int? ?? 0;
                final bool isSelected = _selectedRecIds.contains(malId);

                final score = rec['score'] ?? rec['averageScore'] ?? 0;
                final dynamic genresValue = rec['genres'];
                final List<dynamic> rawGenres = (genresValue is List)
                    ? genresValue
                    : (genresValue is String &&
                            genresValue.trim().isNotEmpty)
                        ? genresValue
                            .split(',')
                            .map((s) => s.trim())
                            .toList()
                        : <dynamic>[];
                final genresDisplay = _formatList(rawGenres);
                
                String _inferType(List<dynamic> genres) {
                  if (genres.isEmpty) return 'TV';
                  final g = genres.first.toString().toLowerCase();
                  if (g.contains('movie')) return 'Movie';
                  if (g.contains('ova') || g.contains('special')) return 'OVA/Special';
                  return 'TV';
                }

                final animeTypeSubtitle = rec['type'] ?? rec['format'] ?? _inferType(rawGenres);

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Card(
                    key: ValueKey(malId),
                    color: isSelected
                        ? const Color(0xFF3E497A).withOpacity(0.9)
                        : const Color(0xFF7A8DB5),
                    elevation: 4,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: isSelected
                          ? const BorderSide(color: Colors.redAccent, width: 2)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      onTap: () => _toggleSelection(malId),
                      contentPadding: const EdgeInsets.all(10),
                      leading: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: isSelected
                                ? Colors.redAccent
                                : const Color(0xFF3E497A),
                            radius: 20,
                            child: Text('${index + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (isSelected)
                            ScaleTransition(
                              scale: _iconScaleAnimation,
                              child: const Icon(
                                Icons.check_circle,
                                color: Colors.yellow,
                                size: 40,
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        rec['title'] ??
                            widget.tr('recommendations_title_default'),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          decoration: isSelected
                              ? TextDecoration.underline
                              : null,
                          decorationColor: Colors.white70,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.tr('recommendations_score_label')} ${(score / 10.0).toStringAsFixed(1)} / 10.0',
                            style: const TextStyle(
                                color: Colors.yellow, fontSize: 13),
                          ),
                          Text(
                            '${widget.tr('recommendations_type_label')} $animeTypeSubtitle',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${widget.tr('recommendations_genres_label')} $genresDisplay',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _cleanDescription(rec['description'] ??
                                widget.tr(
                                    'recommendations_description_default')),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}