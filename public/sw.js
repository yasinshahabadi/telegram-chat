// public/sw.js

self.addEventListener('install', event => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', event => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', event => {
  event.waitUntil(
    (async () => {
      try {
        const data = event.data ? event.data.json() : {};
        const title = data.title || 'پیام جدید';

        // Do not notify while the chat page is actually visible.
        // A hidden/locked Android PWA is intentionally NOT treated as visible.
        const clientList = await self.clients.matchAll({
          type: 'window',
          includeUncontrolled: true
        });

        const isAppVisible = clientList.some(client => {
          return client.visibilityState === 'visible';
        });

        if (isAppVisible) {
          return;
        }

        const messageId = data.messageId || crypto.randomUUID();
        const options = {
          body: data.body || 'شما یک پیام جدید دارید',
          icon: '/icon.svg',
          badge: '/icon.svg',
          silent: false,
          vibrate: [200, 100, 200],
          tag: `chat-message-${messageId}`,
          renotify: true,
          data: {
            url: data.url || '/',
            messageId
          }
        };

        await self.registration.showNotification(title, options);
      } catch (err) {
        console.error('Push notification error:', err);
      }
    })()
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();

  const targetUrl =
    (event.notification.data && event.notification.data.url) || '/';

  event.waitUntil(
    self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true
    }).then(async clientList => {
      for (const client of clientList) {
        if (
          client.url &&
          client.url.startsWith(self.location.origin) &&
          'focus' in client
        ) {
          await client.focus();
          return client;
        }
      }

      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }

      return undefined;
    })
  );
});
