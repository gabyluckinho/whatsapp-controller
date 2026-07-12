import path from "node:path";
import { chromium, BrowserContext, Page } from "playwright";
import { IBrowserDriver, SendTextParams, SendMediaParams, IncomingMessage } from "./BrowserDriver";
import { WhatsAppSelectors } from "./selectors/whatsappSelectors";
import { getStableFingerprint, hardenContext, RECOMMENDED_LAUNCH_ARGS } from "./antiDetection";
import { humanDelay, humanType, simulatePresence, microDelay } from "../utils/humanBehavior";
import { VOLUMES_BASE_PATH, WHATSAPP_WEB_URL, QR_TIMEOUT_MS } from "../config/constants";
import { logger } from "../utils/logger";
import { attachIncomingMessageListener } from "./listeners/incomingMessageListener";

interface SessionRuntime {
  context: BrowserContext;
  page: Page;
  lastQr: string | null;
  connected: boolean;
  connectedAt: number | null;
  incomingHandlers: Array<(msg: IncomingMessage) => void>;
  disconnectHandlers: Array<() => void>;
  healthCheckTimer: NodeJS.Timeout | null;
}

/**
 * Implementação real do IBrowserDriver usando Playwright + Chromium.
 * Cada sessão = 1 BrowserContext PERSISTENTE (perfil próprio em disco),
 * garantindo que reiniciar o container não derrube o login (requisito
 * de persistência) e que cada sessão tenha fingerprint estável (antiDetection).
 */
export class PlaywrightDriver implements IBrowserDriver {
  private sessions = new Map<string, SessionRuntime>();

  private profileDir(sessionId: string): string {
    return path.join(VOLUMES_BASE_PATH, `session-${sessionId}`, "profile");
  }

  async startSession(sessionId: string): Promise<void> {
    if (this.sessions.has(sessionId)) {
      logger.warn({ sessionId }, "Sessão já iniciada, ignorando novo start");
      return;
    }

    const { viewport, userAgent } = getStableFingerprint(sessionId);

    const context = await chromium.launchPersistentContext(this.profileDir(sessionId), {
      headless: true,
      viewport,
      userAgent,
      locale: "pt-BR",
      timezoneId: "America/Cuiaba",
      args: RECOMMENDED_LAUNCH_ARGS,
    });

    await hardenContext(context);

    const page = context.pages()[0] ?? (await context.newPage());

    const runtime: SessionRuntime = {
      context,
      page,
      lastQr: null,
      connected: false,
      connectedAt: null,
      incomingHandlers: [],
      disconnectHandlers: [],
      healthCheckTimer: null,
    };
    this.sessions.set(sessionId, runtime);

    await page.goto(WHATSAPP_WEB_URL, { waitUntil: "domcontentloaded" });
    await simulatePresence(page);

    await this.watchForQrOrLoad(sessionId, runtime);
    await this.attachIncomingMessageListener(sessionId, runtime);
    this.attachDisconnectionWatcher(sessionId, runtime);
    this.startHealthCheck(sessionId, runtime);

    logger.info({ sessionId }, "Sessão iniciada");
  }

  async stopSession(sessionId: string): Promise<void> {
    const runtime = this.sessions.get(sessionId);
    if (!runtime) return;
    if (runtime.healthCheckTimer) clearInterval(runtime.healthCheckTimer);
    await runtime.context.close();
    this.sessions.delete(sessionId);
    logger.info({ sessionId }, "Sessão finalizada");
  }

  async getQrCode(sessionId: string): Promise<string | null> {
    return this.sessions.get(sessionId)?.lastQr ?? null;
  }

  async isConnected(sessionId: string): Promise<boolean> {
    return this.sessions.get(sessionId)?.connected ?? false;
  }

  async requestPairingCode(sessionId: string, phoneNumber: string): Promise<string> {
    const runtime = this.requireRuntime(sessionId);
    const { page } = runtime;
    const digitsOnly = phoneNumber.replace(/\D/g, "");

    if (digitsOnly.length < 10) {
      throw new Error("Número de telefone inválido — inclua o código do país (ex: 5511999999999)");
    }

    const trigger = page.getByText(WhatsAppSelectors.linkWithPhoneTrigger).first();
    await trigger.waitFor({ state: "visible", timeout: 20_000 });
    await simulatePresence(page);
    await trigger.click();
    await microDelay(500, 1000);

    const phoneInput = page.locator(WhatsAppSelectors.phoneNumberInput).first();
    await phoneInput.waitFor({ state: "visible", timeout: 10_000 });
    await humanType(page, WhatsAppSelectors.phoneNumberInput, digitsOnly);
    await microDelay(300, 700);

    const nextBtn = page.getByText(WhatsAppSelectors.nextButton).first();
    await nextBtn.click();

    const codeEl = page.locator(WhatsAppSelectors.pairingCodeText).first();
    await codeEl.waitFor({ state: "visible", timeout: 20_000 });
    const code = (await codeEl.textContent())?.trim() ?? "";

    if (!code) {
      throw new Error("Não foi possível ler o código de pareamento na tela — o layout do WhatsApp Web pode ter mudado");
    }

    logger.info({ sessionId }, "Código de pareamento gerado");
    return code;
  }

  onIncomingMessage(sessionId: string, handler: (msg: IncomingMessage) => void): void {
    const runtime = this.sessions.get(sessionId);
    runtime?.incomingHandlers.push(handler);
  }

  onDisconnected(sessionId: string, handler: () => void): void {
    const runtime = this.sessions.get(sessionId);
    runtime?.disconnectHandlers.push(handler);
  }

  async sendText({ sessionId, contact, text }: SendTextParams): Promise<void> {
    const runtime = this.requireRuntime(sessionId);
    const { page } = runtime;

    await this.openChat(page, contact);
    await simulatePresence(page);
    await humanDelay();

    await humanType(page, WhatsAppSelectors.messageInput, text);
    await microDelay(150, 400);
    await page.locator(WhatsAppSelectors.sendButton).click();

    logger.info({ sessionId, contact }, "Mensagem de texto enviada");
  }

  async sendImage(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "image");
  }

  async sendAudio(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "audio");
  }

  async sendDocument(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "document");
  }

  async sendVideo(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "video");
  }

  // ---------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------

  private requireRuntime(sessionId: string): SessionRuntime {
    const runtime = this.sessions.get(sessionId);
    if (!runtime) {
      throw new Error(`Sessão ${sessionId} não está ativa. Chame startSession primeiro.`);
    }
    return runtime;
  }

  private async openChat(page: Page, contact: string): Promise<void> {
    await page.locator(WhatsAppSelectors.chatSearchInput).click();
    await humanType(page, WhatsAppSelectors.chatSearchInput, contact);
    await microDelay(400, 900);
    await page.keyboard.press("Enter");
    await microDelay(300, 700);
  }

  private async sendMedia(
    { sessionId, contact, filePath, caption }: SendMediaParams,
    _kind: "image" | "audio" | "document" | "video"
  ): Promise<void> {
    const runtime = this.requireRuntime(sessionId);
    const { page } = runtime;

    await this.openChat(page, contact);
    await simulatePresence(page);
    await humanDelay();

    await page.locator(WhatsAppSelectors.attachButton).click();
    await microDelay(200, 500);

    const fileInput = page.locator(WhatsAppSelectors.attachDocumentInput).first();
    await fileInput.setInputFiles(filePath);
    await microDelay(500, 1200);

    if (caption) {
      await humanType(page, WhatsAppSelectors.messageInput, caption);
    }

    await microDelay(150, 400);
    await page.locator(WhatsAppSelectors.sendButton).click();

    logger.info({ sessionId, contact, filePath }, "Mídia enviada");
  }

  private async watchForQrOrLoad(sessionId: string, runtime: SessionRuntime): Promise<void> {
    const { page } = runtime;
    const deadline = Date.now() + QR_TIMEOUT_MS;
    let qrWasShown = false;

    while (Date.now() < deadline) {
      const loggedIn = await page.locator(WhatsAppSelectors.loggedInIndicator).count();
      if (loggedIn > 0) {
        runtime.connected = true;
        runtime.connectedAt = Date.now();
        runtime.lastQr = null;
        return;
      }

      const qrCanvas = page.locator(WhatsAppSelectors.qrCodeCanvas);
      const qrCount = await qrCanvas.count();

      if (qrCount > 0) {
        qrWasShown = true;
        try {
          const qrDataUrl = await qrCanvas.evaluate((el) => (el as HTMLCanvasElement).toDataURL());
          runtime.lastQr = qrDataUrl;
        } catch {
          // canvas pode estar re-renderizando; tenta de novo no próximo loop
        }
      } else if (qrWasShown) {
        // O QR estava visível e sumiu — é a prova de que o celular escaneou
        // com sucesso. NÃO esperamos a lista de conversas terminar de
        // sincronizar pra considerar "conectado": a sincronização pode levar
        // bem mais tempo (depende do volume de mensagens) e não é necessária
        // pra já começar a enviar/receber mensagens pela automação.
        runtime.connected = true;
        runtime.connectedAt = Date.now();
        runtime.lastQr = null;
        logger.info({ sessionId }, "QR escaneado — conectado (sincronização de conversas pode continuar em segundo plano)");
        return;
      }

      await microDelay(1000, 1500);
    }

    logger.warn({ sessionId }, "Timeout aguardando QR code / carregamento da sessão");
  }

  private async attachIncomingMessageListener(sessionId: string, runtime: SessionRuntime): Promise<void> {
    try {
      await attachIncomingMessageListener(runtime.page, sessionId, (msg) => {
        runtime.incomingHandlers.forEach((handler) => handler(msg));
      });
    } catch (error) {
      logger.error({ sessionId, error }, "Falha ao anexar listener de mensagens recebidas");
    }
  }

  private attachDisconnectionWatcher(sessionId: string, runtime: SessionRuntime): void {
    const handleDisconnect = (reason: string) => {
      if (!runtime.connected) return;
      runtime.connected = false;
      runtime.disconnectHandlers.forEach((h) => h());
      logger.warn({ sessionId, reason }, "Sessão desconectada");
    };

    runtime.page.on("close", () => handleDisconnect("página fechou"));
    runtime.context.on("close", () => handleDisconnect("navegador encerrou"));
  }

  private startHealthCheck(sessionId: string, runtime: SessionRuntime): void {
    const GRACE_PERIOD_MS = 90_000;

    runtime.healthCheckTimer = setInterval(async () => {
      if (!runtime.connected) return;
      if (runtime.connectedAt && Date.now() - runtime.connectedAt < GRACE_PERIOD_MS) return;

      try {
        const stillLoggedIn = await runtime.page.locator(WhatsAppSelectors.loggedInIndicator).count();
        if (stillLoggedIn === 0) {
          runtime.connected = false;
          runtime.disconnectHandlers.forEach((h) => h());
          logger.warn({ sessionId }, "Sessão perdeu login (detectado via checagem ativa)");
        }
      } catch (error) {
        logger.warn({ sessionId, error }, "Falha ao checar saúde da sessão (tentativa isolada)");
      }
    }, 20_000);
  }
}
