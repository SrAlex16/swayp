import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/repositories/ratings_repository.dart';
import '../../domain/models/domain.dart';
import '../../domain/models/user_profile.dart';
import '../domain_selection/current_domain_provider.dart';
import '../saved/saved_provider.dart';
import 'profile_provider.dart';

/// Rango de edad válido — igual que MIN_AGE/MAX_AGE de
/// src/api/routes/profile_routes.py, validado aquí también antes de enviar
/// nada al backend.
const int minAge = 1;
const int maxAge = 120;

/// Valida el campo de edad del formulario de Perfil. `null` si es válido
/// (incluye el caso de campo vacío: la edad es opcional). Función pura y
/// testeable, usada como `validator` del `TextFormField` de edad.
String? validateAge(String? rawValue) {
  final trimmed = rawValue?.trim() ?? '';
  if (trimmed.isEmpty) return null;

  final parsed = int.tryParse(trimmed);
  if (parsed == null) return 'Introduce un número entero';
  if (parsed < minAge || parsed > maxAge) {
    return 'La edad debe estar entre $minAge y $maxAge';
  }
  return null;
}

/// Pantalla de Perfil (docs/ARCHITECTURE.md secciones 4 y 7.2): datos de
/// perfil, gustos declarados explícitamente por dominio, tema de la app (
/// movido aquí desde el menú de Descubrir) y el reset del algoritmo de
/// recomendación.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domain = ref.watch(currentDomainProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Tu perfil'),
          const _ProfileForm(),
          const SizedBox(height: 32),
          if (domain != null) ...[
            _SectionTitle('Tus gustos en ${domain.displayName}'),
            _PreferencesSection(domain: domain),
            const SizedBox(height: 32),
          ],
          const _SectionTitle('Tema'),
          const _ThemeSection(),
          const SizedBox(height: 32),
          if (domain != null) ...[
            const _SectionTitle('Zona de peligro'),
            _DangerZoneSection(domain: domain),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm();

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _genderController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _ageController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  void _initializeFrom(UserProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _ageController.text = profile.age?.toString() ?? '';
    _genderController.text = profile.gender ?? '';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final ageText = _ageController.text.trim();
    final age = ageText.isEmpty ? null : int.parse(ageText);
    final genderText = _genderController.text.trim();
    final gender = genderText.isEmpty ? null : genderText;

    setState(() => _saving = true);
    final error = await ref.read(profileProvider.notifier).save(age: age, gender: gender);
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error == null ? 'Perfil guardado' : error.message)));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Text(
        error is AppException ? error.message : 'No se pudo cargar el perfil.',
      ),
      data: (profile) {
        _initializeFrom(profile);
        return Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(labelText: 'Edad'),
                keyboardType: TextInputType.number,
                validator: validateAge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _genderController,
                decoration: const InputDecoration(labelText: 'Género (opcional)'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreferencesSection extends ConsumerStatefulWidget {
  const _PreferencesSection({required this.domain});

  final Domain domain;

  @override
  ConsumerState<_PreferencesSection> createState() => _PreferencesSectionState();
}

class _PreferencesSectionState extends ConsumerState<_PreferencesSection> {
  final _tagController = TextEditingController();

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _addTag() async {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    _tagController.clear();

    final error = await ref.read(preferencesProvider.notifier).addPreference(tag);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  }

  Future<void> _removeTag(String tag) async {
    final error = await ref.read(preferencesProvider.notifier).removePreference(tag);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  }

  @override
  Widget build(BuildContext context) {
    final preferencesAsync = ref.watch(preferencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preferencesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Text(
            error is AppException ? error.message : 'No se pudieron cargar tus gustos.',
          ),
          data: (preferences) => preferences.isEmpty
              ? const Text('Todavía no has declarado ningún gusto en este dominio.')
              : Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final preference in preferences)
                      Chip(
                        label: Text(preference.tag),
                        onDeleted: () => _removeTag(preference.tag),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                decoration: const InputDecoration(labelText: 'Añadir un gusto'),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            IconButton(icon: const Icon(Icons.add), tooltip: 'Añadir', onPressed: _addTag),
          ],
        ),
      ],
    );
  }
}

/// Selector Sistema/Claro/Oscuro (antes vivía en el menú de Descubrir, ver
/// docs/ARCHITECTURE.md sección 7.1 — se movió aquí porque Perfil es el
/// sitio más contextual para los ajustes de la app).
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);

    return RadioGroup<ThemeMode>(
      groupValue: currentMode,
      onChanged: (value) {
        if (value == null) return;
        ref.read(themeModeProvider.notifier).setThemeMode(value);
      },
      child: Column(
        children: [
          for (final mode in ThemeMode.values)
            RadioListTile<ThemeMode>(
              title: Text(_themeModeLabel(mode)),
              value: mode,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Sistema',
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Oscuro',
  };
}

class _DangerZoneSection extends ConsumerWidget {
  const _DangerZoneSection({required this.domain});

  final Domain domain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
      onPressed: () => _confirmAndReset(context, ref),
      child: Text('Reiniciar recomendaciones de ${domain.displayName}'),
    );
  }

  Future<void> _confirmAndReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Reiniciar recomendaciones?'),
        content: Text(
          'Se borrarán todas tus valoraciones de ${domain.displayName}, incluida tu lista de '
          'Guardados. Tus preferencias explícitas y tu blacklist no se ven afectadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final deletedCount = await ref.read(ratingsRepositoryProvider).resetRatings(domain.code);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Se han borrado $deletedCount valoraciones')));
      ref.invalidate(savedProvider);
    } on AppException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
