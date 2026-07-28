import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const String _mobileDefaultServerAddress = '192.168.110.159';
  static const String _desktopDefaultServerAddress = 'localhost';
  static const int defaultPort = 8080;

  static String get defaultServerAddress {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      return normalizeBaseUrl(override);
    }
    return normalizeBaseUrl(_platformDefaultServerAddress);
  }

  static String get defaultApiBaseUrl => normalizeBaseUrl(defaultServerAddress);

  static String normalizeAddress(String input) {
    return normalizeBaseUrl(input);
  }

  static String normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    final candidate = trimmed.isEmpty ? _platformDefaultServerAddress : trimmed;
    final hasExplicitScheme = candidate.contains('://');
    final withScheme = hasExplicitScheme ? candidate : 'http://$candidate';
    final parsed = Uri.parse(withScheme);
    final host = parsed.host.isEmpty
        ? _platformDefaultServerAddress
        : parsed.host;
    final scheme = parsed.scheme.isEmpty ? 'http' : parsed.scheme;
    final pathSegments = parsed.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();

    final normalized = Uri(
      scheme: scheme,
      host: host,
      port: parsed.hasPort
          ? parsed.port
          : hasExplicitScheme
          ? null
          : defaultPort,
      pathSegments: pathSegments.isEmpty ? null : pathSegments,
    );

    return normalized.toString();
  }

  static String get _platformDefaultServerAddress {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return _desktopDefaultServerAddress;
    }
    return _mobileDefaultServerAddress;
  }
}
