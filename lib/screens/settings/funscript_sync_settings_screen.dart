import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../services/funscript_sync_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';

/// Configures the locally hosted FunScriptSync API used by the player overlay.
class FunScriptSyncSettingsScreen extends StatefulWidget {
  const FunScriptSyncSettingsScreen({super.key});

  @override
  State<FunScriptSyncSettingsScreen> createState() => _FunScriptSyncSettingsScreenState();
}

class _FunScriptSyncSettingsScreenState extends State<FunScriptSyncSettingsScreen> with ControllerDisposerMixin {
  final _formKey = GlobalKey<FormState>();
  late final _serverUrlController = createTextEditingController();
  late final _secretController = createTextEditingController();
  final _serverUrlFocus = FocusNode(debugLabel: 'FunScriptSync:ServerUrl');
  final _secretFocus = FocusNode(debugLabel: 'FunScriptSync:Secret');
  final _testFocus = FocusNode(debugLabel: 'FunScriptSync:Test');
  bool _loading = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _serverUrlFocus.addListener(_saveWhenEditingEnds);
    _secretFocus.addListener(_saveWhenEditingEnds);
    _load();
  }

  @override
  void dispose() {
    _serverUrlFocus.removeListener(_saveWhenEditingEnds);
    _secretFocus.removeListener(_saveWhenEditingEnds);
    _serverUrlFocus.dispose();
    _secretFocus.dispose();
    _testFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await FunScriptSyncService.instance.loadConfig();
    if (!mounted) return;
    _serverUrlController.text = config.serverUrl;
    _secretController.text = config.secret;
    setState(() => _loading = false);
  }

  void _saveWhenEditingEnds() {
    if (_serverUrlFocus.hasFocus || _secretFocus.hasFocus) return;
    unawaited(_saveSilently());
  }

  Future<void> _saveSilently() async {
    try {
      await FunScriptSyncService.instance.saveConfig(
        serverUrl: _serverUrlController.text,
        secret: _secretController.text,
      );
    } on FunScriptSyncConfigurationException {
      // Incomplete values remain visible and are saved after editing finishes.
    } catch (error) {
      debugPrint('[FunScriptSync] Automatic settings save failed: $error');
    }
  }

  Future<void> _testConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _testing = true);
    try {
      await FunScriptSyncService.instance.testConnection(
        serverUrl: _serverUrlController.text,
        secret: _secretController.text,
      );
      await FunScriptSyncService.instance.saveConfig(
        serverUrl: _serverUrlController.text,
        secret: _secretController.text,
      );
      if (mounted) showSuccessSnackBar(context, t.funscriptSync.connectionSuccessful);
    } on FunScriptSyncConfigurationException catch (error) {
      if (mounted) showErrorSnackBar(context, error.message);
    } on FunScriptSyncRequestException catch (error) {
      if (mounted) showErrorSnackBar(context, error.message);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: Text(t.funscriptSync.title),
      children: [
        SettingsGroup(
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: LoadingIndicatorBox()),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FocusableTextFormField(
                        controller: _serverUrlController,
                        focusNode: _serverUrlFocus,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        onFieldSubmitted: (_) => _secretFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: t.funscriptSync.serverUrl,
                          hintText: 'http://192.168.178.50:3000',
                          helperText: t.funscriptSync.serverUrlHelper,
                          prefixIcon: const AppIcon(Symbols.link_rounded, fill: 1),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty ? t.addServer.required : null,
                      ),
                      const SizedBox(height: 16),
                      FocusableTextFormField(
                        controller: _secretController,
                        focusNode: _secretFocus,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _testConnection(),
                        decoration: InputDecoration(
                          labelText: t.funscriptSync.secret,
                          helperText: t.funscriptSync.secretHelper,
                          prefixIcon: const AppIcon(Symbols.key_rounded, fill: 1),
                        ),
                        validator: (value) => value == null || value.isEmpty ? t.addServer.required : null,
                      ),
                      const SizedBox(height: 20),
                      FocusableButton(
                        focusNode: _testFocus,
                        useBackgroundFocus: true,
                        onPressed: _testing ? null : _testConnection,
                        child: FilledButton.icon(
                          onPressed: _testing ? null : _testConnection,
                          icon: _testing
                              ? const LoadingIndicatorBox()
                              : const AppIcon(Symbols.network_check_rounded, fill: 1),
                          label: Text(_testing ? t.funscriptSync.testing : t.funscriptSync.testConnection),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
