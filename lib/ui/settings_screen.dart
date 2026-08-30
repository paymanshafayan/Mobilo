import 'package:flutter/material.dart';

import '../core/ai_settings.dart';
import '../core/fa.dart';
import '../services/contacts_service.dart';
import '../services/voice_assistant.dart';

/// App settings. First item: AI model configuration (per-section
/// provider + model), then general toggles.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AiSettings? _settings;

  /// 0 = never asked, 1 = granted, 2 = denied.
  int _contactsStatus = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await AiSettings.load();
    final granted = await const ContactsService().hasPermission();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _contactsStatus = granted ? 1 : 0;
    });
  }

  Future<void> _toggleReadAloud(bool value) async {
    final settings = _settings!;
    setState(() => settings.readAloud = value);
    await settings.setReadAloud(value);
  }

  Future<void> _toggleWakeWord(bool value) async {
    final settings = _settings!;
    setState(() => settings.wakeWordEnabled = value);
    await settings.setWakeWordEnabled(value);
    await VoiceAssistant.instance.refresh();
  }

  Future<void> _toggleVoiceTts(bool value) async {
    final settings = _settings!;
    setState(() => settings.voiceTtsEnabled = value);
    await settings.setVoiceTtsEnabled(value);
  }

  Future<void> _requestContacts() async {
    final service = const ContactsService();
    final granted = await service.ensurePermission();
    if (!mounted) return;
    setState(() => _contactsStatus = granted ? 1 : 2);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final scheme = Theme.of(context).colorScheme;

    final chatModel = settings.modelFor(AiSettings.sectionChat);
    final searchModel = settings.modelFor(AiSettings.sectionWebSearch);

    return Scaffold(
      appBar: AppBar(title: Text(Strings.settingsTitle)),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.model_training,
                    color: scheme.onPrimaryContainer),
              ),
              title: Text(Strings.settingsModel),
              subtitle: Text(
                '${Strings.settingsSectionChat}: $chatModel\n'
                '${Strings.settingsSectionSearch}: $searchModel',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ModelSettingsScreen()),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: SwitchListTile(
              secondary: Icon(Icons.volume_up, color: scheme.primary),
              title: Text(Strings.settingsReadAloud),
              subtitle: Text(Strings.settingsReadAloudSub),
              value: settings.readAloud,
              onChanged: _toggleReadAloud,
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                  child: Row(
                    children: [
                      Icon(Icons.graphic_eq, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(Strings.settingsVoiceTitle,
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: Text(Strings.settingsWakeWord),
                  subtitle: Text(Strings.settingsWakeWordSub),
                  value: settings.wakeWordEnabled,
                  onChanged: _toggleWakeWord,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(Strings.settingsVoiceTts),
                  subtitle: Text(Strings.settingsVoiceTtsSub),
                  value: settings.voiceTtsEnabled,
                  onChanged: _toggleVoiceTts,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.contacts,
                      color: _contactsStatus == 1
                          ? scheme.primary
                          : scheme.onSurfaceVariant),
                  title: Text(Strings.settingsContacts),
                  subtitle: Text(switch (_contactsStatus) {
                    1 => Strings.settingsContactsGranted,
                    2 => Strings.settingsContactsDenied,
                    _ => Strings.settingsContactsNone,
                  }),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: _requestContacts,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    Strings.settingsVoiceExample,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Strings.settingsPrivacy,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    Strings.settingsPrivacyText,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Model configuration: per-section provider + model pickers and
/// provider management (built-in Groq + OpenAI-compatible providers).
class ModelSettingsScreen extends StatefulWidget {
  const ModelSettingsScreen({super.key});

  @override
  State<ModelSettingsScreen> createState() => _ModelSettingsScreenState();
}

class _ModelSettingsScreenState extends State<ModelSettingsScreen> {
  AiSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await AiSettings.load();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _setSection(
      String sectionId, String providerId, String modelId) async {
    final settings = _settings!;
    await settings.setSection(sectionId, providerId, modelId);
    setState(() {});
  }

  Future<void> _addProvider() async {
    final created = await _providerDialog(context, AiSettings.newCustom());
    if (created == null || !mounted) return;
    final settings = _settings!;
    await settings.addProvider(created);
    setState(() {});
  }

  Future<void> _editProvider(AiProviderDef provider) async {
    final updated = await _providerDialog(context, provider);
    if (updated == null || !mounted) return;
    final settings = _settings!;
    if (provider.builtin) {
      // Built-in: only the key and model list are user-editable.
      await settings.updateProvider(AiProviderDef.groq.copyWith(
        apiKey: updated.apiKey,
        models: updated.models.isEmpty
            ? AiProviderDef.groq.models
            : updated.models,
      ));
    } else {
      await settings.updateProvider(updated);
    }
    setState(() {});
  }

  Future<void> _deleteProvider(AiProviderDef provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Strings.settingsDelete),
        content: Text('${Strings.settingsDeleteConfirm} ${provider.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(Strings.settingsDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _settings!.removeProvider(provider.id);
    setState(() {});
  }

  Future<AiProviderDef?> _providerDialog(
      BuildContext context, AiProviderDef initial) async {
    final nameCtrl = TextEditingController(text: initial.name);
    final urlCtrl = TextEditingController(text: initial.baseUrl);
    final keyCtrl = TextEditingController(text: initial.apiKey);
    final modelsCtrl = TextEditingController(text: initial.models.join(', '));
    final isNew = initial.id == 'custom-new';

    return showGeneralDialog<AiProviderDef>(
      context: context,
      pageBuilder: (context, _, __) => AlertDialog(
        title: Text(isNew ? Strings.settingsAddProvider : Strings.settingsEditProvider),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                enabled: !initial.builtin,
                decoration: InputDecoration(
                    labelText: Strings.settingsProviderName,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                enabled: !initial.builtin,
                decoration: InputDecoration(
                    labelText: Strings.settingsProviderBaseUrl,
                    hintText: 'https://api.groq.com/openai/v1',
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: Strings.settingsProviderKey,
                    helperText: initial.builtin && initial.apiKey.isEmpty
                        ? Strings.settingsKeyFromBuild
                        : null,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelsCtrl,
                decoration: InputDecoration(
                    labelText: Strings.settingsProviderModels,
                    hintText: 'qwen/qwen3-32b, groq/compound',
                    border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              final models = modelsCtrl.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              Navigator.of(context).pop(AiProviderDef(
                id: isNew ? 'p-${DateTime.now().millisecondsSinceEpoch}' : initial.id,
                name: nameCtrl.text.trim().isEmpty
                    ? (initial.builtin ? initial.name : 'Custom')
                    : nameCtrl.text.trim(),
                baseUrl: initial.builtin
                    ? initial.baseUrl
                    : (urlCtrl.text.trim().isEmpty
                        ? 'https://api.openai.com/v1'
                        : urlCtrl.text.trim()),
                apiKey: keyCtrl.text.trim(),
                models: models,
                builtin: initial.builtin,
              ));
            },
            child: Text(Strings.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      // AppBar has no const constructor, so this Scaffold cannot be const.
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(Strings.settingsModel)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionCard(
            title: Strings.settingsSectionChat,
            icon: Icons.chat_bubble_outline,
            sectionId: AiSettings.sectionChat,
            settings: settings,
            onChanged: _setSection,
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: Strings.settingsSectionSearch,
            icon: Icons.public,
            sectionId: AiSettings.sectionWebSearch,
            settings: settings,
            onChanged: _setSection,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Strings.settingsProviders,
                  style: Theme.of(context).textTheme.titleMedium),
              FilledButton.tonalIcon(
                onPressed: _addProvider,
                icon: const Icon(Icons.add),
                label: Text(Strings.settingsAddProviderShort),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final provider in settings.providers)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: provider.builtin
                      ? scheme.primaryContainer
                      : scheme.secondaryContainer,
                  child: Text(
                    provider.name.isEmpty ? '?' : provider.name[0].toUpperCase(),
                    style: TextStyle(
                        color: provider.builtin
                            ? scheme.onPrimaryContainer
                            : scheme.onSecondaryContainer),
                  ),
                ),
                title: Text(
                  provider.name,
                ),
                subtitle: Text(
                  '${provider.baseUrl}\n'
                  '${provider.hasKey
                      ? (provider.keyFromBuild
                          ? Strings.settingsKeyFromBuild
                          : Strings.settingsKeySet)
                      : Strings.settingsNoKey}',
                  maxLines: 2,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: Strings.settingsEditProvider,
                      onPressed: () => _editProvider(provider),
                    ),
                    if (!provider.builtin)
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: scheme.error),
                        tooltip: Strings.settingsDelete,
                        onPressed: () => _deleteProvider(provider),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One section (chat / web search / future): provider + model pickers.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.sectionId,
    required this.settings,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final String sectionId;
  final AiSettings settings;
  final Future<void> Function(String sectionId, String providerId,
      String modelId) onChanged;

  @override
  Widget build(BuildContext context) {
    final cfg = settings.section(sectionId);
    final provider = settings.providerFor(sectionId);

    // The model picker offers the provider's models; if the currently
    // selected model is not in that list (e.g. user typed it before),
    // keep it visible as well.
    final models = List<String>.of(provider.models);
    if (!models.contains(cfg.modelId)) models.add(cfg.modelId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: cfg.providerId,
              decoration: const InputDecoration(
                labelText: Strings.settingsProvider,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final p in settings.providers)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (id) {
                if (id == null) return;
                final newProvider =
                    settings.providers.firstWhere((p) => p.id == id);
                final model = newProvider.models.isNotEmpty
                    ? newProvider.models.first
                    : cfg.modelId;
                onChanged(sectionId, id, model);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: models.contains(cfg.modelId) ? cfg.modelId : null,
              decoration: const InputDecoration(
                labelText: Strings.settingsModelName,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final m in models)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (id) {
                if (id == null) return;
                onChanged(sectionId, cfg.providerId, id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
