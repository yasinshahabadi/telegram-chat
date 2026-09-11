// lib/config.dart

class AppConfig {
  // TODO: آدرس دامنه کلودفلر خود را اینجا قرار دهید (بدون اسلش پایانی)
  static const String baseUrl = "https://telegram-chat-staging.yasinshahabadi007.workers.dev";
  static const String botUsername = "chattransfer_test_bot";

  static String get wsUrl {
    if (baseUrl.startsWith("https://")) {
      return baseUrl.replaceFirst("https://", "wss://") + "/api/ws";
    } else {
      return baseUrl.replaceFirst("http://", "ws://") + "/api/ws";
    }
  }
}