// This service worker is required to expose an exported Godot project as a
// Progressive Web App. It provides an offline fallback page telling the user
// that they need an Internet connection to run the project if desired.
// Incrementing CACHE_VERSION will kick off the install event and force
// previously cached resources to be updated from the network.
/** @type {string} */
const CACHE_VERSION = '1794359845|2125797';
/** @type {string} */
const CACHE_PREFIX = 'Lethebar-sw-cache-';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;

// Each payload file sits in its own cache, named after its bytes.
const PAYLOAD_PREFIX = "Lethebar-payload-";
const PAYLOAD = {
	"index.wasm": "Lethebar-payload-wasm-fc74679e3b97",
	"index.pck": "Lethebar-payload-pck-8fb3b2601465"
};
/** @type {string} */
const OFFLINE_URL = 'index.offline.html';
/** @type {boolean} */
const ENSURE_CROSSORIGIN_ISOLATION_HEADERS = false;
// Files that will be cached on load.
/** @type {string[]} */
const CACHED_FILES = ["index.html", "index.js", "index.offline.html", "index.icon.png", "index.apple-touch-icon.png", "index.audio.worklet.js", "index.audio.position.worklet.js"];
// Files that we might not want the user to preload, and will only be cached on first load.
/** @type {string[]} */
const CACHEABLE_FILES = [];
const FULL_CACHE = CACHED_FILES.concat(CACHEABLE_FILES);

self.addEventListener('install', (event) => {
	event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));
});

self.addEventListener('activate', (event) => {
	event.waitUntil(caches.keys().then(
		function (keys) {
			// Remove old caches.
			const keep = Object.values(PAYLOAD);
			return Promise.all(keys
				.filter((key) =>
					(key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME) ||
					(key.startsWith(PAYLOAD_PREFIX) && !keep.includes(key)))
				.map((key) => caches.delete(key)));
		}
	).then(function () {
		// Enable navigation preload if available.
		return ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();
	}));
});

/**
 * Ensures that the response has the correct COEP/COOP headers
 * @param {Response} response
 * @returns {Response}
 */
function ensureCrossOriginIsolationHeaders(response) {
	if (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'
		&& response.headers.get('Cross-Origin-Opener-Policy') === 'same-origin') {
		return response;
	}

	const crossOriginIsolatedHeaders = new Headers(response.headers);
	crossOriginIsolatedHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
	crossOriginIsolatedHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
	const newResponse = new Response(response.body, {
		status: response.status,
		statusText: response.statusText,
		headers: crossOriginIsolatedHeaders,
	});

	return newResponse;
}

/**
 * Calls fetch and cache the result if it is cacheable
 * @param {FetchEvent} event
 * @param {Cache} cache
 * @param {boolean} isCacheable
 * @returns {Response}
 */
async function fetchAndCache(event, cache, isCacheable) {
	// Use the preloaded response, if it's there
	/** @type { Response } */
	let response = await event.preloadResponse;
	if (response == null) {
		// Or, go over network.
		response = await self.fetch(event.request);
	}

	if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
		response = ensureCrossOriginIsolationHeaders(response);
	}

	if (isCacheable) {
		// And update the cache
		cache.put(event.request, response.clone());
	}

	return response;
}

self.addEventListener(
	'fetch',
	/**
	 * Triggered on fetch
	 * @param {FetchEvent} event
	 */
	(event) => {
		const isNavigate = event.request.mode === 'navigate';
		const url = event.request.url || '';
		const referrer = event.request.referrer || '';
		const base = referrer.slice(0, referrer.lastIndexOf('/') + 1);
		const local = url.startsWith(base) ? url.replace(base, '') : '';
		const isCacheable = FULL_CACHE.some((v) => v === local) || PAYLOAD[local] !== undefined || (base === referrer && base.endsWith(CACHED_FILES[0]));
		if (isNavigate || isCacheable) {
			event.respondWith((async () => {
				// Try to use cache first
				const cache = await caches.open(CACHE_NAME);
				const payloadCache = PAYLOAD[local];
				if (payloadCache !== undefined) {
					const store = await caches.open(payloadCache);
					const hit = await store.match(event.request);
					if (hit != null) {
						return hit;
					}
					const fetched = await fetch(event.request);
					if (fetched.ok) {
						store.put(event.request, fetched.clone()).catch((error) => {
							self.lethebarCacheError = String((error && error.message) || error);
						});
					}
					return fetched;
				}
				if (isNavigate) {
					// Check if we have full cache during HTML page request.
					/** @type {Response[]} */
					const fullCache = await Promise.all(FULL_CACHE.map((name) => cache.match(name)));
					const missing = fullCache.some((v) => v === undefined);
				// The payload is not in this cache; a navigation is only safe when
				// every payload file is already stored in its own cache.
				const payloadMissing = (
					await Promise.all(
						Object.keys(PAYLOAD).map(async (name) =>
							(await (await caches.open(PAYLOAD[name])).match(name)) === undefined)
					)
				).some(Boolean);
					if (missing || payloadMissing) {
						try {
							// Try network if some cached file is missing (so we can display offline page in case).
							const response = await fetchAndCache(event, cache, isCacheable);
							return response;
						} catch (e) {
							// And return the hopefully always cached offline page in case of network failure.
							console.error('Network error: ', e); // eslint-disable-line no-console
							const document = await cache.match(CACHED_FILES[0]);
							return document != null ? document : caches.match(OFFLINE_URL);
						}
					}
				}
				let cached = await cache.match(event.request);
				if (cached == null && isNavigate) {
					// A player arrives at the directory URL (/lethebar/), which is a
					// different cache key than index.html. Without this fallback every
					// navigation misses the cache, goes to the network and fails offline
					// (iOS Safari reports it as "FetchEvent.respondWith received an
					// error: TypeError: Load failed").
					//
					// Only a document URL gets the document. Answering any navigation
					// with it turned /lethebar/test-pack.zip into the game instead of a
					// download, because `isNavigate` covers every top level navigation.
					const target = new URL(event.request.url).pathname;
					if (target.endsWith('/') || target.endsWith('/index.html')) {
						cached = await cache.match(CACHED_FILES[0]);
					}
				}
				if (cached != null) {
					if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
						cached = ensureCrossOriginIsolationHeaders(cached);
					}
					return cached;
				}
				// Try network if don't have it in cache.
				const response = await fetchAndCache(event, cache, isCacheable);
				return response;
			})());
		} else if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
			event.respondWith((async () => {
				let response = await fetch(event.request);
				response = ensureCrossOriginIsolationHeaders(response);
				return response;
			})());
		}
	}
);

self.addEventListener('message', (event) => {
	// No cross origin
	if (event.origin !== self.origin) {
		return;
	}
	const id = event.source.id || '';
	const msg = event.data || '';
	// Ensure it's one of our clients.
	self.clients.get(id).then(function (client) {
		if (!client) {
			return; // Not a valid client.
		}
		if (msg === 'claim') {
			self.skipWaiting().then(() => self.clients.claim());
		} else if (msg === 'clear') {
			caches.delete(CACHE_NAME);
		} else if (msg === 'update') {
			self.skipWaiting().then(() => self.clients.claim()).then(() => self.clients.matchAll()).then((all) => all.forEach((c) => c.navigate(c.url)));
		}
	});
});


// A page cannot read a worker's globals, so it asks. The answer says whether the
// payload is really in its cache and what the browser said when a write failed;
// the landing screen turns the second fact into a sentence (REQ-031).
self.lethebarCacheError = self.lethebarCacheError || "";
self.addEventListener("message", (event) => {
	if (!event.data || event.data.type !== "lethebar-cache-state") {
		return;
	}
	const reply = event.ports && event.ports[0];
	(async () => {
		const stored = [];
		for (const name of Object.keys(PAYLOAD)) {
			if ((await caches.has(PAYLOAD[name])) && (await (await caches.open(PAYLOAD[name])).match(name))) {
				stored.push(name);
			}
		}
		if (reply) {
			reply.postMessage({
				controlled: true,
				stored,
				error: self.lethebarCacheError || "",
			});
		}
	})();
});
