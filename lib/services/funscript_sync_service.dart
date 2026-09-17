import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'base_shared_preferences_service.dart';
import 'credential_vault.dart';
import 'sensitive_prefs.dart';

/// Settings and HTTP client for the optional local FunScriptSync server.
///
/// The Stash API credential deliberately stays on FunScriptSync. Plezy only
/// holds the shared webhook secret needed to authenticate its delete request.
class FunScriptSyncService {
  FunScriptSyncService._();

  static final instance = FunScriptSyncService._();

  static const _serverUrlPref = 'funscript_sync_server_url';
  static const _connectionTestPath = 'connection-test';
  static const _activeSceneStatusPath = 'active-scene/status';
  static const _deleteActiveScenePath = 'active-scene/delete';

  Future<FunScriptSyncConfig> loadConfig() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final serverUrl = readTolerantString(prefs, _serverUrlPref)?.trim() ?? '';
    final protectedSecret = readTolerantString(prefs, funscriptSyncSecretPref) ?? '';
    final secret = protectedSecret.isEmpty ? '' : await CredentialVault.reveal(protectedSecret) ?? '';
    return FunScriptSyncConfig(serverUrl: serverUrl, secret: secret);
  }

  Future<void> saveConfig({required String serverUrl, required String secret}) async {
    final normalizedUrl = _normalizeServerUrl(serverUrl);
    if (normalizedUrl == null) {
      throw const FunScriptSyncConfigurationException('Ungültige FunScriptSync-Server-Adresse.');
    }
    if (secret.isEmpty) {
      throw const FunScriptSyncConfigurationException('Das FunScriptSync-Secret darf nicht leer sein.');
    }

    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_serverUrlPref, normalizedUrl);
    await prefs.setString(funscriptSyncSecretPref, await CredentialVault.protect(secret));
  }

  /// Verifies reachability and the shared secret without changing server state.
  Future<void> testConnection({required String serverUrl, required String secret}) async {
    final normalizedUrl = _normalizeServerUrl(serverUrl);
    if (normalizedUrl == null) {
      throw const FunScriptSyncConfigurationException('UngÃ¼ltige FunScriptSync-Server-Adresse.');
    }
    if (secret.isEmpty) {
      throw const FunScriptSyncConfigurationException('Das FunScriptSync-Secret darf nicht leer sein.');
    }

    final uri = Uri.parse('$normalizedUrl/$_connectionTestPath');
    debugPrint('[FunScriptSync] GET $uri');
    try {
      final response = await http
          .get(uri, headers: {'X-FunScriptSync-Secret': secret, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      debugPrint('[FunScriptSync] Connection test response ${response.statusCode}: ${response.body.trim()}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['ok'] == true && decoded['service'] == 'FunScriptSync') return;
        throw const FunScriptSyncRequestException('Der Server hat keine gÃ¼ltige FunScriptSync-Antwort gesendet.');
      }
      throw FunScriptSyncRequestException(_responseMessage(response));
    } on TimeoutException {
      throw const FunScriptSyncRequestException('ZeitÃ¼berschreitung beim Verbinden mit FunScriptSync.');
    } on FunScriptSyncRequestException {
      rethrow;
    } catch (error) {
      throw FunScriptSyncRequestException('Verbindung zu FunScriptSync fehlgeschlagen: $error');
    }
  }

  /// Requests deletion of the scene currently active on FunScriptSync.
  Future<void> deleteActiveScene() async {
    final config = await loadConfig();
    if (!config.isConfigured) {
      throw const FunScriptSyncConfigurationException('FunScriptSync ist nicht eingerichtet.');
    }

    final uri = Uri.parse('${config.serverUrl}/$_deleteActiveScenePath');
    debugPrint('[FunScriptSync] POST $uri');
    final response = await http
        .post(uri, headers: {'X-FunScriptSync-Secret': config.secret, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    debugPrint('[FunScriptSync] Response ${response.statusCode}: ${response.body.trim()}');
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw FunScriptSyncRequestException(_responseMessage(response));
  }

  /// Reads the source of the Funscript currently active on FunScriptSync.
  Future<FunScriptSyncSceneStatus?> getActiveSceneStatus() async {
    final config = await loadConfig();
    if (!config.isConfigured) return null;

    final uri = Uri.parse('${config.serverUrl}/$_activeSceneStatusPath');
    final response = await http
        .get(uri, headers: {'X-FunScriptSync-Secret': config.secret, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FunScriptSyncRequestException(_responseMessage(response));
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Expected an object');
      final source = switch (decoded['source']) {
        'stash' => FunScriptSyncScriptSource.stash,
        'audio' => FunScriptSyncScriptSource.audio,
        'fallback' => FunScriptSyncScriptSource.fallback,
        _ => null,
      };
      return FunScriptSyncSceneStatus(
        loading: decoded['loading'] == true,
        source: source,
        deviceConnected: decoded['deviceConnected'] == true,
      );
    } catch (error) {
      throw FunScriptSyncRequestException('Ungültige Statusantwort von FunScriptSync: $error');
    }
  }

  String _responseMessage(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return 'FunScriptSync antwortete mit HTTP ${response.statusCode}.';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = decoded['error'] ?? decoded['message'];
        if (message is String && message.trim().isNotEmpty) return message.trim();
      }
    } catch (_) {
      // Plain-text error responses are part of the existing webhook contract.
    }
    return body;
  }

  String? _normalizeServerUrl(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null || !parsed.hasAuthority || (parsed.scheme != 'http' && parsed.scheme != 'https')) return null;
    return parsed.toString().replaceFirst(RegExp(r'/+$'), '');
  }
}

class FunScriptSyncConfig {
  final String serverUrl;
  final String secret;

  const FunScriptSyncConfig({required this.serverUrl, required this.secret});

  bool get isConfigured => serverUrl.isNotEmpty && secret.isNotEmpty;
}

enum FunScriptSyncScriptSource { stash, audio, fallback }

class FunScriptSyncSceneStatus {
  final bool loading;
  final FunScriptSyncScriptSource? source;
  final bool deviceConnected;

  const FunScriptSyncSceneStatus({required this.loading, required this.source, required this.deviceConnected});
}

class FunScriptSyncConfigurationException implements Exception {
  final String message;
  const FunScriptSyncConfigurationException(this.message);

  @override
  String toString() => message;
}

class FunScriptSyncRequestException implements Exception {
  final String message;
  const FunScriptSyncRequestException(this.message);

  @override
  String toString() => message;
}
