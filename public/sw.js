// public/sw.js

self.addEventListener('install', event => {
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', event => {
  if (!event.data) return;

  event.waitUntil(
    (async () => {
      try {
        // ۱. بررسی تمام پنجره‌ها و تب‌های باز برنامه
        const clientList = await self.clients.matchAll({
          type: 'window',
          includeUncontrolled: true
        });

        // ۲. آیا تبی از چت وجود دارد که کاربر هم‌اکنون در حال مشاهده و تعامل با آن باشد؟
        const isAppFocused = clientList.some(client => client.focused);

        // ۳. اگر کاربر هم‌اکنون درون صفحه چت است، نوتیفیکیشن سیستمی نمایش داده نشود
        if (isAppFocused) {
          return;
        }

        // ۴. اگر کاربر در صفحه نیست (صفحه در پس‌زمینه است یا مرورگر بسته است)، اعلان نمایش داده شود
        const data = event.data.json();
        const title = data.title || 'پیام جدید';
        const options = {
          body: data.body || 'شما یک پیام جدید دارید',
          icon: '/icon-192.png',
          badge: '/badge-72.png',
          vibrate: [200, 100, 200],
          data: { url: data.url || '/' },
          tag: 'chat-group-message',
          renotify: true
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
  const targetUrl = (event.notification.data && event.notification.data.url) || '/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
      // اگر تب باز وجود دارد، روی همان فوکوس کن
      for (const client of clientList) {
        if (client.url && 'focus' in client) {
          return client.focus();
        }
      }
      // در غیر این صورت یک پنجره جدید باز کن
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
    })
  );
});