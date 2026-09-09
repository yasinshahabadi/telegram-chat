// public/sw.js

const DEFAULT_ICON = '/icon.svg';

function buildTargetUrl(data, action = 'open') {
  try {
    const url = new URL(data.url || '/', self.location.origin);
    if (data.messageId) url.searchParams.set('messageId', data.messageId);
    if (action !== 'open') url.searchParams.set('notificationAction', action);
    return url.pathname + url.search + url.hash;
  } catch (e) {
    return '/';
  }
}

function isSameOrigin(url) {
  try {
    return new URL(url, self.location.origin).origin === self.location.origin;
  } catch (e) {
    return false;
  }
}

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
        const messageId = data.messageId || crypto.randomUUID();

        const clientList = await self.clients.matchAll({
          type: 'window',
          includeUncontrolled: true
        });
        const isAppVisible = clientList.some(client => client.visibilityState === 'visible');
        if (isAppVisible) return;

        const icon = isSameOrigin(data.senderAvatarUrl) ? data.senderAvatarUrl : DEFAULT_ICON;
        const mediaUrl = isSameOrigin(data.mediaUrl) ? data.mediaUrl : null;
        const isImage = data.mediaType === 'photo' && !!mediaUrl;

        const options = {
          body: data.body || 'شما یک پیام جدید دارید',
          icon,
          badge: DEFAULT_ICON,
          silent: false,
          vibrate: [200, 100, 200],
          tag: `chat-message-${messageId}`,
          renotify: true,
          dir: 'rtl',
          lang: 'fa',
          data: {
            url: data.url || '/',
            messageId,
            senderName: data.senderName || '',
            mediaType: data.mediaType || null,
            mediaUrl
          },
          actions: [
            { action: 'reply', title: 'پاسخ' }
          ]
        };

        if (isImage) options.image = mediaUrl;

        await self.registration.showNotification(title, options);
      } catch (err) {
        console.error('Push notification error:', err);
      }
    })()
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();

  const data = event.notification.data || {};
  const action = event.action || 'open';
  const targetUrl = buildTargetUrl(data, action);

  event.waitUntil((async () => {
    const clientList = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true
    });

    for (const client of clientList) {
      if (
        !client.url ||
        !client.url.startsWith(self.location.origin) ||
        !('focus' in client)
      ) continue;

      await client.focus();

      // Reply is intentionally handled through postMessage when the PWA is
      // already open. This avoids relying on client.navigate(), which can make
      // an action look identical to a normal notification click on Android.
      if (action === 'reply' && 'postMessage' in client) {
        client.postMessage({
          type: 'notification-action',
          action: 'reply',
          messageId: data.messageId || null
        });
        return client;
      }

      // Normal notification click: open/focus the exact message.
      if (action === 'open' && 'navigate' in client) {
        try { await client.navigate(targetUrl); } catch (e) {}
      }
      return client;
    }

    // If the PWA is not open, opening the action-specific URL lets the page
    // complete the reply flow after it has initialized.
    if (self.clients.openWindow) {
      return self.clients.openWindow(targetUrl);
    }
    return undefined;
  })());
});
