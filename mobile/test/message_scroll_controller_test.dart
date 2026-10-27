import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/state/message_scroll_controller.dart';

/// لیست تست: آیتم‌ها ارتفاع متغیر دارند تا شرایط واقعی چت (پیام کوتاه/بلند)
/// شبیه‌سازی شود.
List<ChatMessageModel> _buildMessages(int count) {
  final now = DateTime(2026, 10, 24, 12).millisecondsSinceEpoch;
  return List<ChatMessageModel>.generate(count, (index) {
    return ChatMessageModel(
      id: 'msg-$index',
      senderId: index.isEven ? 'me' : 'other',
      senderName: index.isEven ? 'من' : 'دیگری',
      text: 'پیام شماره $index',
      // لیست از جدید به قدیم است.
      createdAt: now - index * 60000,
      updatedAt: now - index * 60000,
    );
  });
}

/// ارتفاع‌های عمداً نامنظم؛ یک پیام بسیار بلند (شبیه اسکرین‌شات) هم دارد.
double _heightFor(int index) {
  if (index == 9) return 900;
  if (index == 21) return 460;
  return 56.0 + (index % 4) * 38.0;
}

Widget _buildChatList({
  required List<ChatMessageModel> messages,
  required ScrollController controller,
  required MessageScrollController scrollController,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: ListView.builder(
          controller: controller,
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return KeyedSubtree(
              key: scrollController.anchorFor(message.id),
              child: RepaintBoundary(
                key: ValueKey(message.id),
                child: Container(
                  height: _heightFor(index),
                  alignment: Alignment.center,
                  color: index.isEven
                      ? Colors.blueGrey.shade100
                      : Colors.blueGrey.shade50,
                  child: Text('پیام ${message.id}'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// اجرای پرش و پمپ کردن فریم‌ها تا پایان کار (بدون وابستگی به setTimeout).
Future<MessageScrollResult> _jumpAndSettle(
  WidgetTester tester,
  Future<MessageScrollResult> future,
) async {
  MessageScrollResult? result;
  Object? error;
  var completed = false;

  future.then((value) {
    result = value;
    completed = true;
  }).catchError((Object e) {
    error = e;
    completed = true;
  });

  for (var frame = 0; frame < 400 && !completed; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  expect(completed, isTrue, reason: 'پرش در زمان مورد انتظار تمام نشد');
  expect(error, isNull, reason: 'پرش نباید استثنا پرتاب کند');
  return result!;
}

void main() {
  testWidgets(
    'jump to a very old message puts the beginning of that message at the top',
    (tester) async {
      final messages = _buildMessages(40);
      final scrollController = ScrollController();
      final messageScroll = MessageScrollController();

      await tester.pumpWidget(_buildChatList(
        messages: messages,
        controller: scrollController,
        scrollController: messageScroll,
      ));
      await tester.pump();

      // از پایین (جدیدترین پیام‌ها) شروع می‌کنیم.
      expect(scrollController.offset, 0);

      const targetId = 'msg-32';
      final result = await _jumpAndSettle(
        tester,
        messageScroll.scrollToMessage(
          messageId: targetId,
          readMessages: () => messages,
          scrollController: scrollController,
        ),
      );

      expect(result, MessageScrollResult.reached);
      // جهت درست: به سمت پیام‌های قدیمی (offset بزرگ‌تر).
      expect(scrollController.offset, greaterThan(0));

      final targetTop =
          tester.getTopLeft(find.byKey(messageScroll.anchorFor(targetId))).dy;
      expect(targetTop, closeTo(0, 0.5));

      // پیام جدیدتر (index کمتر) پایین‌تر از مقصد قرار می‌گیرد و باید دیده شود.
      final newerTop =
          tester.getTopLeft(find.byKey(messageScroll.anchorFor('msg-31'))).dy;
      expect(newerTop, greaterThan(targetTop));
    },
  );

  testWidgets(
    'jump works for a middle message with tall neighbors',
    (tester) async {
      final messages = _buildMessages(40);
      final scrollController = ScrollController();
      final messageScroll = MessageScrollController();

      await tester.pumpWidget(_buildChatList(
        messages: messages,
        controller: scrollController,
        scrollController: messageScroll,
      ));
      await tester.pump();

      const targetId = 'msg-21';
      final result = await _jumpAndSettle(
        tester,
        messageScroll.scrollToMessage(
          messageId: targetId,
          readMessages: () => messages,
          scrollController: scrollController,
        ),
      );

      expect(result, MessageScrollResult.reached);
      final targetTop =
          tester.getTopLeft(find.byKey(messageScroll.anchorFor(targetId))).dy;
      expect(targetTop, closeTo(0, 0.5));
    },
  );

  testWidgets(
    'jump back to a newer message while scrolled far up',
    (tester) async {
      final messages = _buildMessages(40);
      final scrollController = ScrollController();
      final messageScroll = MessageScrollController();

      await tester.pumpWidget(_buildChatList(
        messages: messages,
        controller: scrollController,
        scrollController: messageScroll,
      ));
      await tester.pump();

      final upResult = await _jumpAndSettle(
        tester,
        messageScroll.scrollToMessage(
          messageId: 'msg-35',
          readMessages: () => messages,
          scrollController: scrollController,
        ),
      );
      expect(upResult, MessageScrollResult.reached);

      final downResult = await _jumpAndSettle(
        tester,
        messageScroll.scrollToMessage(
          messageId: 'msg-3',
          readMessages: () => messages,
          scrollController: scrollController,
        ),
      );

      expect(downResult, MessageScrollResult.reached);
      // نزدیک‌ترین پیام به انتهای لیست است؛ پس اسکرول تا پایین می‌رود و پیام
      // به‌طور کامل دیده می‌شود (نمی‌توان ابتدای آن را بالای صفحه آورد).
      expect(scrollController.offset, 0);

      final targetFinder = find.byKey(messageScroll.anchorFor('msg-3'));
      final targetTop = tester.getTopLeft(targetFinder).dy;
      final targetBottom = tester.getBottomLeft(targetFinder).dy;
      expect(targetTop, greaterThanOrEqualTo(0));
      expect(targetBottom, lessThanOrEqualTo(600));
    },
  );

  testWidgets(
    'jump converges even when unbuilt messages are much taller than the first screen',
    (tester) async {
      // شبیه‌سازی چت با پیام‌های بلندِ ساخته‌نشده: تخمین اولیهٔ Flutter از
      // maxScrollExtent بسیار کمتر از واقعیت است.
      final messages = _buildMessages(200);
      final scrollController = ScrollController();
      final messageScroll = MessageScrollController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: scrollController,
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final height = index < 10 ? 50.0 : 900.0;
              return KeyedSubtree(
                key: messageScroll.anchorFor(message.id),
                child: SizedBox(
                  height: height,
                  child: Text('پیام ${message.id}'),
                ),
              );
            },
          ),
        ),
      ));
      await tester.pump();

      const targetId = 'msg-190';
      final result = await _jumpAndSettle(
        tester,
        messageScroll.scrollToMessage(
          messageId: targetId,
          readMessages: () => messages,
          scrollController: scrollController,
        ),
      );

      expect(result, MessageScrollResult.reached);
      final targetTop =
          tester.getTopLeft(find.byKey(messageScroll.anchorFor(targetId))).dy;
      expect(targetTop, closeTo(0, 0.5));
    },
  );

  testWidgets(
    'a deleted reply target is reported without scrolling or throwing',
    (tester) async {
      final messages = _buildMessages(20);
      final scrollController = ScrollController();
      final messageScroll = MessageScrollController();

      await tester.pumpWidget(_buildChatList(
        messages: messages,
        controller: scrollController,
        scrollController: messageScroll,
      ));
      await tester.pump();

      final result = await _jumpAndSettle(
        tester,
        messageScroll.scrollToMessage(
          messageId: 'deleted-message-id',
          readMessages: () => messages,
          scrollController: scrollController,
        ),
      );

      expect(result, MessageScrollResult.notInList);
      expect(scrollController.offset, 0);
    },
  );

  testWidgets(
    'a newer jump cancels the previous one',
    (tester) async {
      final messages = _buildMessages(50);
      final scrollController = ScrollController();
      final messageScroll = MessageScrollController();

      await tester.pumpWidget(_buildChatList(
        messages: messages,
        controller: scrollController,
        scrollController: messageScroll,
      ));
      await tester.pump();

      final first = messageScroll.scrollToMessage(
        messageId: 'msg-45',
        readMessages: () => messages,
        scrollController: scrollController,
      );
      await tester.pump(const Duration(milliseconds: 16));

      final second = messageScroll.scrollToMessage(
        messageId: 'msg-10',
        readMessages: () => messages,
        scrollController: scrollController,
      );

      final firstResult = await _jumpAndSettle(tester, first);
      final secondResult = await _jumpAndSettle(tester, second);

      expect(firstResult, MessageScrollResult.cancelled);
      expect(secondResult, MessageScrollResult.reached);
      final targetTop =
          tester.getTopLeft(find.byKey(messageScroll.anchorFor('msg-10'))).dy;
      expect(targetTop, closeTo(0, 0.5));
    },
  );
}
