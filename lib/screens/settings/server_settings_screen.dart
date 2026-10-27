import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/data_refresh.dart';
import '../../services/api_config.dart';
import '../../services/api_exception.dart';
import '../../services/server_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

/// Lets the user point the app at a different backend without rebuilding.
///
/// Useful when the laptop's LAN address changes: the build-time default is
/// only a fallback, and the saved value survives app restarts.
class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;

  bool _testing = false;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ref.read(serverConfigProvider).baseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    try {
      normalizeServerUrl(value ?? '');
      return null;
    } on FormatException catch (e) {
      return e.message.toString();
    }
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _error = null;
      _success = null;
    });

    try {
      final url = normalizeServerUrl(_url.text);
      await checkServer(url);
      if (!mounted) return;
      setState(() => _success = 'Server reachable at $url');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    try {
      final config = ref.read(serverConfigProvider);
      final previous = config.baseUrl;
      await config.setBaseUrl(_url.text);
      ref.read(serverUrlProvider.notifier).state = config.baseUrl;

      // Saved data belongs to the old backend.
      if (config.baseUrl != previous) {
        await ref.read(localCacheProvider).clear();
        ref.read(cacheStatusProvider).reset();
      }
      invalidateRemoteData(ref);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(e);
      });
    }
  }

  Future<void> _reset() async {
    final config = ref.read(serverConfigProvider);
    final previous = config.baseUrl;
    await config.reset();
    ref.read(serverUrlProvider.notifier).state = config.baseUrl;

    if (config.baseUrl != previous) {
      await ref.read(localCacheProvider).clear();
      ref.read(cacheStatusProvider).reset();
    }
    _url.text = config.baseUrl;
    invalidateRemoteData(ref);

    if (!mounted) return;
    setState(() {
      _error = null;
      _success = 'Using the built-in default.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final custom = ref.watch(serverConfigProvider).isCustom;
    final busy = _testing || _saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 20, color: AppColors.primary),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "This phone talks to the CP Tracker backend over "
                            "Wi-Fi. Enter your computer's LAN address, for "
                            "example http://192.168.1.17:8000. Both devices "
                            "must be on the same network.",
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.17:8000',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  validator: _validate,
                  onChanged: (_) {
                    if (_success != null || _error != null) {
                      setState(() {
                        _success = null;
                        _error = null;
                      });
                    }
                  },
                  onFieldSubmitted: (_) {
                    if (!busy) _save();
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, height: 1.35),
                  ),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _success!,
                    style:
                        const TextStyle(color: AppColors.success, height: 1.35),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: busy ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Test connection'),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Save',
                  loading: _saving,
                  onPressed: _testing ? null : _save,
                ),
                if (custom) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : _reset,
                    child: const Text('Reset to built-in default'),
                  ),
                ],
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Built-in default: ${ApiConfig.baseUrl}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
