// lib/widgets/blacklist_overlay.dart
import 'package:flutter/material.dart';
import '../services/blacklist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class BlacklistOverlay extends StatefulWidget {
  final String Function(String) tr;
  const BlacklistOverlay({super.key, required this.tr});

  @override
  State<BlacklistOverlay> createState() => _BlacklistOverlayState();
}

class _BlacklistOverlayState extends State<BlacklistOverlay> {
  List<Map<String, dynamic>> _blacklistItems = [];
  final Set<int> _selected = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    
    try {
      // Obtener IDs de la blacklist (MAL_IDs)
      final malIds = await BlacklistService.getBlacklist();
      
      // Cargar títulos desde caché
      final items = <Map<String, dynamic>>[];
      final prefs = await SharedPreferences.getInstance();
      
      for (final malId in malIds) {
        String title = 'Anime MAL ID $malId'; // Valor por defecto
        
        // 🔥 Buscar título en caché de usuarios guardados
        final savedUsers = prefs.getStringList('saved_users') ?? [];
        for (final user in savedUsers) {
          final cachedDataStr = prefs.getString('recommendations_data_$user');
          if (cachedDataStr != null) {
            try {
              final cachedData = json.decode(cachedDataStr) as Map<String, dynamic>;
              final recs = cachedData['recommendations'] as List<dynamic>?;
              
              if (recs != null) {
                // Buscar el anime por MAL_ID
                final anime = recs.firstWhere(
                  (rec) => (rec as Map<String, dynamic>)['MAL_ID'] == malId,
                  orElse: () => null,
                );
                
                if (anime != null) {
                  title = (anime as Map<String, dynamic>)['title'] as String? ?? title;
                  break; // Encontramos el título, salir del loop
                }
              }
            } catch (e) {
              // Error parseando caché, continuar con siguiente usuario
              continue;
            }
          }
        }
        
        items.add({
          'MAL_ID': malId,
          'title': title,
        });
      }
      
      setState(() {
        _blacklistItems = items;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando blacklist: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeSelected() async {
    if (_selected.isEmpty) return;
    
    // Mostrar diálogo de confirmación
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF3E497A),
        title: Text(
          widget.tr('confirm_removal'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          '${widget.tr('remove_confirmation')} ${_selected.length} ${widget.tr('animes_from_blacklist')}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              widget.tr('cancel'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            child: Text(
              widget.tr('remove'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    try {
      await BlacklistService.removeFromBlacklist(_selected.toList());
      await _load();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.tr('blacklist_remove_success')),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _selected.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.tr('error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF3E497A),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.tr('view_blacklist'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Contador
              if (!_isLoading && _blacklistItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    '${_blacklistItems.length} ${widget.tr('animes_in_blacklist')}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              
              // Lista
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      )
                    : _blacklistItems.isEmpty
                        ? Center(
                            child: Text(
                              widget.tr('blacklist_empty'),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _blacklistItems.length,
                            itemBuilder: (_, idx) {
                              final item = _blacklistItems[idx];
                              final malId = item['MAL_ID'] as int;
                              final isSelected = _selected.contains(malId);
                              
                              return Card(
                                color: isSelected
                                    ? const Color(0xFF5D709D).withOpacity(0.8)
                                    : const Color(0xFF5D709D),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: isSelected
                                      ? const BorderSide(
                                          color: Colors.yellow,
                                          width: 2,
                                        )
                                      : BorderSide.none,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? Colors.yellow
                                        : const Color(0xFF3E497A),
                                    child: Text(
                                      '${idx + 1}',
                                      style: TextStyle(
                                        color: isSelected
                                            ? const Color(0xFF3E497A)
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    item['title'] as String,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'MAL ID: $malId',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.yellow,
                                          size: 28,
                                        )
                                      : null,
                                  onTap: () => setState(() {
                                    _selected.contains(malId)
                                        ? _selected.remove(malId)
                                        : _selected.add(malId);
                                  }),
                                ),
                              );
                            },
                          ),
              ),
              
              const SizedBox(height: 12),
              
              // Botón de eliminar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selected.isEmpty ? null : _removeSelected,
                  icon: const Icon(Icons.delete),
                  label: Text(
                    _selected.isEmpty
                        ? widget.tr('select_animes')
                        : '${widget.tr('remove_from_blacklist')} (${_selected.length})',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selected.isEmpty
                        ? Colors.grey
                        : Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}