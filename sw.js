self.addEventListener('install', event => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', event => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', event => {
  let payload = {};
  if (event.data) {
    try {
      payload = event.data.json();
    } catch {
      payload = { body: event.data.text() };
    }
  }

  const options = {
    body: payload.body || 'Ou gen yon nouvo mesaj.',
    icon: new URL('assets/Image1.jpg', self.registration.scope).href,
    badge: new URL('assets/Image1.jpg', self.registration.scope).href,
    tag: payload.tag || 'morpio-message',
    renotify: true,
    silent: false,
    data: { url: payload.url || './index.html' }
  };
  event.waitUntil(self.registration.showNotification(payload.title || 'Morp.io HT', options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const destination = new URL(event.notification.data?.url || './index.html', self.registration.scope);
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async clients => {
    const client = clients.find(item => new URL(item.url).origin === destination.origin);
    if (client) {
      await client.navigate(destination.href);
      return client.focus();
    }
    return self.clients.openWindow(destination.href);
  }));
});
