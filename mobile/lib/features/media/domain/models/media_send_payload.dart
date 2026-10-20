import 'picked_media.dart';

/// نتیجهٔ صفحهٔ پیش‌نمایش رسانه برای ارسال.
class MediaSendPayload {
  final List<PickedMedia> media;
  final String caption;

  const MediaSendPayload({
    required this.media,
    this.caption = '',
  });
}
