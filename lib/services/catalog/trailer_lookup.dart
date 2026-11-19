import 'dart:async';

import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';

/// Retries transient search failures once. A valid response without a match
/// returns null immediately.
Future<T?> requestTrailer<T>(
  Uri url, {
  required String source,
  required Duration timeout,
  Map<String, String>? headers,
  required T? Function(String body) parse,
}) async {
  for (var attempt = 1; attempt <= 2; attempt++) {
    final client = http.Client();
    try {
      final response = await client.get(url, headers: headers).timeout(timeout);
      final status = response.statusCode;
      if (status == 200) return parse(response.body);
      if (status != 408 && (status < 500 || status >= 600)) {
        appLogger.d('$source trailer search returned HTTP $status');
        return null;
      }
      throw http.ClientException('HTTP $status');
    } catch (error) {
      appLogger.d('$source trailer lookup failed (attempt $attempt of 2)', error: error);
      if (error is! TimeoutException && error is! http.ClientException && error is! FormatException) {
        return null;
      }
    } finally {
      client.close();
    }
    if (attempt == 1) await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return null;
}
