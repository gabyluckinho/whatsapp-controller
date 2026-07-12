export const WHATSAPP_WEB_URL = "https://web.whatsapp.com";

export const VOLUMES_BASE_PATH = process.env.NODE_ENV === "production" ? "/data/sessions" : "./volumes";

/** Lista realista de viewports para variar por sessão (evita fingerprint idêntico entre contexts) */
export const VIEWPORT_POOL = [
  { width: 1366, height: 768 },
  { width: 1440, height: 900 },
  { width: 1536, height: 864 },
  { width: 1600, height: 900 },
];

/** User agents recentes e plausíveis de desktop (rotação por sessão, não por request) */
export const USER_AGENT_POOL = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
];

export const QR_POLL_INTERVAL_MS = 2000;
export const QR_TIMEOUT_MS = 90_000;

export const RECONNECT_BACKOFF_MS = [5_000, 15_000, 30_000, 60_000, 120_000];

