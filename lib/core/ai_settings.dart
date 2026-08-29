import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One API provider (built-in Groq or a user-defined OpenAI-compatible one).
class AiProviderDef {
  const AiProviderDef({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.models = const [],
    this.builtin = false,
  });

  /// Stable identifier used to reference this provider in section configs.
  final String id;

  /// Display name shown in the UI.
  final String name;

  /// OpenAI-compatible base URL, e.g. `https://api.groq.com/openai/v1`.
  /// The client appends `/chat/completions`.
  final String baseUrl;

  /// User-supplied API key. Empty for the built-in Groq -> falls back to
  /// the key injected at build time (GROQ_API_KEY dart-define, fed from the
  /// GitHub repo secret in CI).
  final String apiKey;

  /// Models offered for this provider (model picker entries).
  final List<String> models;

  /// Built-in providers cannot be deleted or rename their endpoint.
  final bool builtin;

  /// The default Groq provider (always the first entry in the list).
  static const AiProviderDef groq = AiProviderDef(
    id: 'groq',
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    builtin: true,
    models: [
      'qwen/qwen3-32b',
      'groq/compound',
      'groq/compound-mini',
      'llama-3.3-70b-versatile',
    ],
  );

  /// The key actually sent to the provider (user override wins over the
  /// build-time secret).
  String get effectiveKey {
    if (apiKey.isNotEmpty) return apiKey;
    if (builtin && id == 'groq') {
      return const String.fromEnvironment('GROQ_API_KEY');
    }
    return '';
  }

  bool get hasKey => effectiveKey.isNotEmpty;

  bool get keyFromBuild =>
      builtin && id == 'groq' && apiKey.isEmpty && hasKey;

  AiProviderDef copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
  }) =>
      AiProviderDef(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        models: models ?? this.models,
        builtin: builtin,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'models': models,
        'builtin': builtin,
      };

  factory AiProviderDef.fromJson(Map<String, dynamic> j) => AiProviderDef(
        id: j['id'] as String? ?? 'custom',
        name: j['name'] as String? ?? 'Custom',
        baseUrl: (j['baseUrl'] as String? ?? '').trim(),
        apiKey: j['apiKey'] as String? ?? '',
        models:
            (j['models'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        builtin: j['builtin'] as bool? ?? false,
      );
}

/// Which provider + model a section (chat / web search / future sections)
/// uses.
class SectionConfig {
  const SectionConfig({required this.providerId, required this.modelId});

  final String providerId;
  final String modelId;

  Map<String, dynamic> toJson() => {'providerId': providerId, 'modelId': modelId};

  factory SectionConfig.fromJson(Map<String, dynamic> j) => SectionConfig(
        providerId: j['providerId'] as String? ?? 'groq',
        modelId: j['modelId'] as String? ?? 'qwen/qwen3-32b',
      );
}

/// App-wide AI configuration, persisted on device (SharedPreferences).
///
/// Sections are intentionally generic: today there is `chat` and
/// `webSearch`; new sections can be added by registering a key here and a
/// card in the settings UI.
class AiSettings {
  AiSettings({
    required this.providers,
    required this.sections,
    this.readAloud = true,
  });

  static const String sectionChat = 'chat';
  static const String sectionWebSearch = 'webSearch';

  static const String _prefsKey = 'ai_settings_v1';

  /// Built-in Groq is always providers.first.
  List<AiProviderDef> providers;

  /// Section id -> (provider, model).
  Map<String, SectionConfig> sections;

  /// Whether AI replies are read aloud by default (TTS toggle).
  bool readAloud;

  static const String defaultChatModel = 'qwen/qwen3-32b';
  static const String defaultSearchModel = 'groq/compound';

  /// Blank provider for the "add provider" dialog.
  static AiProviderDef newCustom() => const AiProviderDef(
        id: 'custom-new',
        name: 'Custom',
        baseUrl: 'https://api.openai.com/v1',
      );

  factory AiSettings.defaults() => AiSettings(
        providers: [AiProviderDef.groq],
        sections: {
          sectionChat: const SectionConfig(
            providerId: 'groq',
            modelId: defaultChatModel,
          ),
          sectionWebSearch: const SectionConfig(
            providerId: 'groq',
            modelId: defaultSearchModel,
          ),
        },
      );

  static Future<AiSettings> load() async {
    final settings = AiSettings.defaults();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return settings;
      final j = jsonDecode(raw) as Map<String, dynamic>;

      final providers = <AiProviderDef>[];
      for (final entry in (j['providers'] as List? ?? [])) {
        if (entry is! Map<String, dynamic>) continue;
        final def = AiProviderDef.fromJson(entry);
        if (def.id == 'groq') {
          // Keep the built-in identity, allow the user's key/model overrides.
          providers.add(AiProviderDef.groq.copyWith(
            apiKey: def.apiKey,
            models: def.models.isEmpty
                ? AiProviderDef.groq.models
                : def.models,
          ));
        } else {
          providers.add(def);
        }
      }
      if (providers.isEmpty) providers.add(AiProviderDef.groq);

      final sections = <String, SectionConfig>{
        sectionChat: const SectionConfig(
          providerId: 'groq',
          modelId: defaultChatModel,
        ),
        sectionWebSearch: const SectionConfig(
          providerId: 'groq',
          modelId: defaultSearchModel,
        ),
      };
      final rawSections = j['sections'];
      if (rawSections is Map<String, dynamic>) {
        rawSections.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            sections[key] = SectionConfig.fromJson(value);
          }
        });
      }
      settings.providers = providers;
      settings.sections = sections;
      settings.readAloud = j['readAloud'] as bool? ?? true;
    } catch (_) {
      // Corrupt storage: fall back to defaults.
    }
    return settings;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({
      'providers': providers.map((p) => p.toJson()).toList(),
      'sections':
          sections.map((k, v) => MapEntry(k, v.toJson())),
      'readAloud': readAloud,
    }));
  }

  SectionConfig section(String id) =>
      sections[id] ?? const SectionConfig(providerId: 'groq', modelId: defaultChatModel);

  /// The provider a section currently uses (falls back to Groq).
  AiProviderDef providerFor(String sectionId) {
    final cfg = section(sectionId);
    for (final p in providers) {
      if (p.id == cfg.providerId) return p;
    }
    return providers.first;
  }

  /// The model a section currently uses (falls back to the provider's first).
  String modelFor(String sectionId) {
    final provider = providerFor(sectionId);
    final cfg = section(sectionId);
    if (provider.models.contains(cfg.modelId)) return cfg.modelId;
    return provider.models.isNotEmpty ? provider.models.first : cfg.modelId;
  }

  Future<void> setSection(String sectionId, String providerId, String modelId) async {
    sections[sectionId] =
        SectionConfig(providerId: providerId, modelId: modelId);
    await save();
  }

  Future<void> addProvider(AiProviderDef provider) async {
    providers.add(provider);
    await save();
  }

  Future<void> updateProvider(AiProviderDef provider) async {
    final index = providers.indexWhere((p) => p.id == provider.id);
    if (index >= 0) {
      providers[index] = provider;
    } else {
      providers.add(provider);
    }
    await save();
  }

  Future<void> removeProvider(String id) async {
    final groq = providers.first;
    providers.removeWhere((p) => p.id == id);
    if (providers.isEmpty) providers.add(groq);
    // Point any section that used the removed provider back to Groq.
    sections.forEach((key, cfg) {
      if (cfg.providerId == id) {
        sections[key] = SectionConfig(
          providerId: 'groq',
          modelId: key == sectionWebSearch ? defaultSearchModel : defaultChatModel,
        );
      }
    });
    await save();
  }

  Future<void> setReadAloud(bool value) async {
    readAloud = value;
    await save();
  }
}
