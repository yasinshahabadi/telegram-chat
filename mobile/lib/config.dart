// lib/config.dart

class AppConfig {
  // TODO: آدرس دامنه کلودفلر خود را اینجا قرار دهید (بدون اسلش پایانی)
  static const String baseUrl = "https://telegram-chat-staging.yasinshahabadi007.workers.dev";
  static const String botUsername = "chattransfer_test_bot";

  static String get wsUrl {
    if (baseUrl.startsWith("https://")) {
      final newUrl = baseUrl.replaceFirst("https://", "wss://");
      return "$newUrl/api/ws";
    } else {
      final newUrl = baseUrl.replaceFirst("http://", "ws://");
      return "$newUrl/api/ws";
    }
  }
}