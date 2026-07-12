import { sessionDefinitions, env } from "../config/env";
import { PlaywrightDriver } from "../playwright/PlaywrightDriver";
import { SessionSupervisor } from "./SessionSupervisor";
import { SessionState } from "./SessionState";
import { LogRepository } from "../database/repositories/LogRepository";
import { MessageRepository } from "../database/repositories/MessageRepository";
import { SessionRepository } from "../database/repositories/SessionRepository";
import { WebhookDispatcher } from "../webhooks/WebhookDispatcher";
import { QueueManager } from "../queue/QueueManager";
import { createSessionWorker } from "../queue/QueueWorker";
import { Worker } from "bullmq";
import { logger } from "../utils/logger";

export class SessionManager {
  private supervisors = new Map<string, SessionSupervisor>();
  private workers = new Map<string, Worker>();
  private readonly driver = new PlaywrightDriver();
  private readonly logRepository = new LogRepository();
  private readonly messageRepository = new MessageRepository();
  private readonly webhookDispatcher = new WebhookDispatcher();
  private readonly sessionRepository = new SessionRepository();
  private readonly queueManager = new QueueManager();

  async initializeAll(): Promise<void> {
    let records = await this.sessionRepository.listActive();

    if (records.length === 0 && sessionDefinitions.length > 0) {
      logger.info({ count: sessionDefinitions.length }, "Tabela sessions vazia — semeando a partir do .env");
      for (const def of sessionDefinitions) {
        await this.sessionRepository.create(def.id, def.name);
      }
      records = await this.sessionRepository.listActive();
    }

    await Promise.allSettled(
      records.map(async (record) => {
        const staggerMs = Math.random() * 4000;
        await new Promise((r) => setTimeout(r, staggerMs));
        await this.bootSession(record.id, record.name);
      })
    );

    logger.info({ total: this.supervisors.size }, "Todas as sessões foram inicializadas (ou tentaram ser)");
  }

  async addSession(id: string, name: string): Promise<SessionSupervisor> {
    if (this.supervisors.has(id)) {
      throw new Error(`Sessão "${id}" já existe`);
    }
    const alreadyInDb = await this.sessionRepository.exists(id);
    if (alreadyInDb) {
      throw new Error(`Já existe uma sessão com o id "${id}" no banco (pode estar inativa)`);
    }

    await this.sessionRepository.create(id, name);
    const supervisor = await this.bootSession(id, name);
    logger.info({ id, name }, "Nova sessão criada pela Plataforma");
    return supervisor;
  }

  async removeSession(id: string): Promise<void> {
    const supervisor = this.requireSession(id);
    await supervisor.stop();

    const worker = this.workers.get(id);
    if (worker) {
      await worker.close();
      this.workers.delete(id);
    }
    await this.queueManager.clear(id);

    this.supervisors.delete(id);
    await this.sessionRepository.deactivate(id);
    logger.info({ id }, "Sessão removida pela Plataforma");
  }

  private async bootSession(id: string, name: string): Promise<SessionSupervisor> {
    const supervisor = new SessionSupervisor(
      id,
      name,
      this.driver,
      this.logRepository,
      this.webhookDispatcher,
      this.messageRepository,
      this.sessionRepository,
      (sessionId, sessionName, newState) => this.notifySessionDown(sessionId, sessionName, newState)
    );
    this.supervisors.set(id, supervisor);

    const worker = createSessionWorker(
      id,
      supervisor.getCreatedAt(),
      this.driver,
      this.webhookDispatcher,
      this.logRepository,
      this.messageRepository
    );
    this.workers.set(id, worker);

    supervisor.start().catch((err) => {
      logger.error({ sessionId: id, err }, "Falha ao iniciar sessão em segundo plano");
    });
    return supervisor;
  }

  get(sessionId: string): SessionSupervisor | undefined {
    return this.supervisors.get(sessionId);
  }

  requireSession(sessionId: string): SessionSupervisor {
    const supervisor = this.supervisors.get(sessionId);
    if (!supervisor) {
      throw new Error(`Sessão "${sessionId}" não encontrada`);
    }
    return supervisor;
  }

  list(): SessionSupervisor[] {
    return Array.from(this.supervisors.values());
  }

  getQueueManager(): QueueManager {
    return this.queueManager;
  }

  async getQrCode(sessionId: string): Promise<string | null> {
    this.requireSession(sessionId);
    return this.driver.getQrCode(sessionId);
  }

  async requestPairingCode(sessionId: string, phoneNumber: string): Promise<string> {
    this.requireSession(sessionId);
    return this.driver.requestPairingCode(sessionId, phoneNumber);
  }

  getDebugScreenshotPath(sessionId: string): string {
    this.requireSession(sessionId);
    return this.driver.getDebugScreenshotPath(sessionId);
  }

  getDebugHtmlPath(sessionId: string): string {
    this.requireSession(sessionId);
    return this.driver.getDebugHtmlPath(sessionId);
  }

  private async notifySessionDown(sessionId: string, sessionName: string, newState: SessionState): Promise<void> {
    if (!env.ADMIN_NOTIFICATION_PHONE) return;

    const messenger = this.list().find((s) => s.sessionId !== sessionId && s.getState() === SessionState.CONECTADO);

    const timestamp = new Date().toLocaleString("pt-BR", { timeZone: "America/Cuiaba" });
    const text =
      `⚠️ Sessão "${sessionName}" (#${sessionId}) mudou para ${newState} às ${timestamp}.\n` +
      `Verifique o painel da Plataforma.`;

    if (!messenger) {
      logger.warn(
        { sessionId },
        "Sessão caiu, mas nenhuma outra sessão está conectada para enviar o aviso via WhatsApp"
      );
      return;
    }

    try {
      await this.driver.sendText({
        sessionId: messenger.sessionId,
        contact: env.ADMIN_NOTIFICATION_PHONE,
        text,
      });
      logger.info({ sessionId, via: messenger.sessionId }, "Aviso de desconexão enviado via WhatsApp");
    } catch (error) {
      logger.error({ sessionId, error }, "Falha ao enviar aviso de desconexão via WhatsApp");
    }
  }
}
