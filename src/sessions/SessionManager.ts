import { sessionDefinitions } from "../config/env";
import { PlaywrightDriver } from "../playwright/PlaywrightDriver";
import { SessionSupervisor } from "./SessionSupervisor";
import { LogRepository } from "../database/repositories/LogRepository";
import { MessageRepository } from "../database/repositories/MessageRepository";
import { SessionRepository } from "../database/repositories/SessionRepository";
import { WebhookDispatcher } from "../webhooks/WebhookDispatcher";
import { QueueManager } from "../queue/QueueManager";
import { createSessionWorker } from "../queue/QueueWorker";
import { Worker } from "bullmq";
import { logger } from "../utils/logger";

/**
 * Ponto único de criação/listagem/controle das sessões — agora DINÂMICO.
 *
 * Antes: a lista de sessões vinha fixa de uma variável de ambiente, exigindo
 * redeploy para adicionar um número novo.
 *
 * Agora: o Supabase (`sessions`) é a fonte de verdade. Na inicialização, o
 * SessionManager lê a tabela; se estiver vazia, semeia com SESSIONS do .env
 * (só para facilitar o primeiro boot). Depois disso, números são
 * adicionados/removidos em tempo real pela Plataforma (dashboard), via
 * addSession()/removeSession(), sem reiniciar o container.
 */
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

    // Stagger entre inicializações: sessões não sobem todas no mesmo instante
    // (reduz padrão de uso robótico e picos de carga na VPS).
    await Promise.allSettled(
      records.map(async (record) => {
        const staggerMs = Math.random() * 4000;
        await new Promise((r) => setTimeout(r, staggerMs));
        await this.bootSession(record.id, record.name);
      })
    );

    logger.info({ total: this.supervisors.size }, "Todas as sessões foram inicializadas (ou tentaram ser)");
  }

  /**
   * Cria uma sessão nova via Plataforma: grava no Supabase, sobe o supervisor
   * e o worker da fila, e retorna imediatamente — o QR code fica disponível
   * em poucos segundos via GET /sessions/:id/qrcode.
   */
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

  /** Remove uma sessão: para o navegador, o worker, e desativa o registro (soft delete). */
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
      this.sessionRepository
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

    // IMPORTANTE: não aguardamos supervisor.start() aqui. Ele pode levar
    // de alguns segundos a minutos até detectar QR/login/timeout, e a API
    // (POST /sessions, usada pelo botão "Adicionar número" do painel) precisa
    // responder na hora — senão a tela trava esperando. O boot do navegador
    // roda em segundo plano; o painel acompanha status/QR via polling.
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
    this.requireSession(sessionId); // valida existência, lança se não encontrada
    return this.driver.getQrCode(sessionId);
  }

  async requestPairingCode(sessionId: string, phoneNumber: string): Promise<string> {
    this.requireSession(sessionId);
    return this.driver.requestPairingCode(sessionId, phoneNumber);
  }
}
