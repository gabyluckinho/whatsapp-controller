import { BrowserContext } from "playwright";
import { USER_AGENT_POOL, VIEWPORT_POOL } from "../config/constants";

/**
 * Escolhe, de forma DETERMINÍSTICA por sessão (mesma sessão sempre pega o mesmo
 * perfil), um viewport e user-agent do pool. Determinístico é importante: uma
 * sessão que muda de fingerprint a cada restart é, ironicamente, MAIS suspeita
 * que uma com identidade estável — o objetivo é parecer um usuário real com um
 * computador real, não uma sessão nova a cada boot.
 */
function pickStableFromPool<T>(pool: T[], sessionId: string): T {
  let hash = 0;
  for (let i = 0; i < sessionId.length; i++) {
    hash = (hash * 31 + sessionId.charCodeAt(i)) >>> 0;
  }
  return pool[hash % pool.length];
}

export function getStableFingerprint(sessionId: string) {
  return {
    viewport: pickStableFromPool(VIEWPORT_POOL, sessionId),
    userAgent: pickStableFromPool(USER_AGENT_POOL, sessionId),
  };
}

/**
 * Aplica scripts de inicialização no contexto para reduzir sinais óbvios de
 * automação (ex.: navigator.webdriver = true é o sinal mais básico e comum
 * checado por qualquer sistema anti-bot). Isso NÃO desativa nenhuma checagem
 * de segurança do WhatsApp nem contorna autenticação — apenas evita o sinal
 * mais grosseiro de "isto é o Chromium controlado por automação".
 */
export async function hardenContext(context: BrowserContext): Promise<void> {
  await context.addInitScript(() => {
    Object.defineProperty(navigator, "webdriver", { get: () => undefined });

    // Alguns sistemas checam plugins/mimeTypes vazios como sinal de headless.
    Object.defineProperty(navigator, "plugins", {
      get: () => [1, 2, 3, 4, 5],
    });
    Object.defineProperty(navigator, "languages", {
      get: () => ["pt-BR", "pt", "en-US", "en"],
    });

    // window.chrome ausente é outro sinal comum em Chromium automatizado.
    // @ts-expect-error - propriedade não tipada no lib.dom
    if (!window.chrome) {
      // @ts-expect-error - propriedade não tipada no lib.dom
      window.chrome = { runtime: {} };
    }
  });
}

/**
 * Opções recomendadas de launch para reduzir superfícies de detecção óbvias.
 * Mantém headless configurável — para ambientes de VPS sem GPU, headless "new"
 * costuma ser suficiente combinado com o hardening acima.
 */
export const RECOMMENDED_LAUNCH_ARGS = [
  "--disable-blink-features=AutomationControlled",
  "--disable-features=IsolateOrigins,site-per-process",
  "--no-sandbox",
  "--disable-dev-shm-usage",
];

