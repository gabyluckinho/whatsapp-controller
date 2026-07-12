import { Page } from "playwright";
import { env } from "../config/env";

/**
 * Camada de "comportamento humano" usada por toda ação que mexe no navegador.
 * Objetivo: reduzir a chance de detecção/banimento por padrão de automação,
 * SEM burlar nenhum mecanismo de segurança do WhatsApp — apenas evitando
 * um padrão de uso obviamente robótico (cadência perfeita, digitação instantânea,
 * zero variação de tempo entre ações).
 */

export function randomBetween(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Delay "humano" entre ações consecutivas na mesma sessão. */
export async function humanDelay(): Promise<void> {
  const ms = randomBetween(env.HUMAN_DELAY_MIN_MS, env.HUMAN_DELAY_MAX_MS);
  await sleep(ms);
}

/** Pequena variação para não repetir exatamente o mesmo delay em ações internas (ex: entre teclas). */
export async function microDelay(minMs = 40, maxMs = 180): Promise<void> {
  await sleep(randomBetween(minMs, maxMs));
}

/**
 * Digita texto em um campo simulando velocidade humana (não usa fill() instantâneo),
 * com pequenas variações de intervalo entre caracteres.
 */
export async function humanType(page: Page, selector: string, text: string): Promise<void> {
  const locator = page.locator(selector);
  await locator.click();
  for (const char of text) {
    await locator.pressSequentially(char, { delay: randomBetween(35, 140) });
    // ocasionalmente uma pausa maior, como alguém pensando
    if (Math.random() < 0.05) {
      await microDelay(200, 600);
    }
  }
}

/**
 * Scroll leve e movimento de mouse antes de uma ação, para gerar eventos de input
 * mais próximos de uso real (o WhatsApp Web, como muitos sistemas anti-bot,
 * observa presença de eventos de mouse/scroll, não só cliques secos).
 */
export async function simulatePresence(page: Page): Promise<void> {
  try {
    const viewport = page.viewportSize();
    if (!viewport) return;
    const x = randomBetween(50, viewport.width - 50);
    const y = randomBetween(50, viewport.height - 50);
    await page.mouse.move(x, y, { steps: randomBetween(5, 15) });
    await microDelay(100, 400);
  } catch {
    // não crítico — se falhar, apenas segue sem simular presença
  }
}

/**
 * Calcula o intervalo mínimo (ms) entre envios de mensagem para uma sessão,
 * respeitando o limite configurado e um período de "aquecimento" para sessões novas.
 */
export function computeMinIntervalMs(sessionCreatedAt: Date): number {
  const hoursSinceCreation = (Date.now() - sessionCreatedAt.getTime()) / (1000 * 60 * 60);
  const isWarmingUp = hoursSinceCreation < env.WARMUP_PERIOD_HOURS;
  const maxPerMinute = isWarmingUp ? env.WARMUP_MAX_MESSAGES_PER_MINUTE : env.MAX_MESSAGES_PER_MINUTE;
  return Math.ceil(60_000 / Math.max(maxPerMinute, 1));
}

