// One-time cleanup for the previous root-level Godot PWA worker. The current
// game lives under ./game/ and the root URL is now a lightweight orientation shell.
self.addEventListener("install", (event) => {
	event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
	event.waitUntil((async () => {
		const oldCachePrefix = "Gravity Run-sw-cache-";
		const cacheNames = await caches.keys();
		await Promise.all(cacheNames
			.filter((cacheName) => cacheName.startsWith(oldCachePrefix))
			.map((cacheName) => caches.delete(cacheName)));

		await self.registration.unregister();
		const clients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
		const scopePath = new URL(self.registration.scope).pathname;
		for (const client of clients) {
			if (new URL(client.url).pathname.startsWith(scopePath)) {
				client.navigate(client.url);
			}
		}
	})());
});
