import { Queue, ConnectionOptions } from "bullmq";
import { env } from "../config/env";
import { computeMinIntervalMs } from "../utils/humanBehavior";

export interface SendMessageJobData {
  sessionId: string;
  contact: string;
  type: "text" | "image" | "audio" | "document" | "video";
  payload: Record<string, unknown>;
}

/**
 * Uma fila Redis (BullMQ) por sessão. O rate limit do BullMQ é configurado
 * dinamicamente por sessão com base no período de "aquecimento" — sessões
 * recém-criadas têm limite de envio bem mais conservador (ver
 * utils/humanBehavior.computeMinIntervalMs), reduzindo o principal gatilho
 * de banimento: volume alto vindo de um número "novo".
 *
 * Passamos apenas as OPÇÕES de conexão (não uma instância de ioredis criada
 * por nós) para o BullMQ — isso evita conflito de tipos entre a versão do
 * ioredis do projeto e a versão interna que o BullMQ empacota, e deixa o
 * BullMQ gerenciar seu próprio ciclo de vida de conexão.
 */
export class QueueManager {
  private connection: ConnectionOptions;
  private queues = new Map<string, Queue<SendMessageJobData>>();

  constructor() {
    this.connection = {
      host: env.REDIS_HOST,
      port: env.REDIS_PORT,
      password: env.REDIS_PASSWORD || undefined,
      maxRetriesPerRequest: null,
    };
  }

  getOrCreateQueue(sessionId: string, sessionCreatedAt: Date): Queue<SendMessageJobData> {
    const existing = this.queues.get(sessionId);
    if (existing) return existing;

    const queue = new Queue<SendMessageJobData>(`session:${sessionId}`, {
      connection: this.connection,
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: "exponential", delay: 5000 },
        removeOnComplete: 200,
        removeOnFail: 500,
      },
    });

    // Guardamos a data de criação junto ao queue para recalcular o limiter
    // dinamicamente (o intervalo mínimo aumenta conforme a sessão "amadurece").
    (queue as unknown as { __sessionCreatedAt: Date }).__sessionCreatedAt = sessionCreatedAt;

    this.queues.set(sessionId, queue);
    return queue;
  }

  /** Intervalo mínimo atual (ms) entre jobs desta sessão, recalculado a cada chamada. */
  getCurrentMinIntervalMs(sessionId: string): number {
    const queue = this.queues.get(sessionId);
    const createdAt = (queue as unknown as { __sessionCreatedAt?: Date })?.__sessionCreatedAt ?? new Date();
    return computeMinIntervalMs(createdAt);
  }

  async enqueue(sessionId: string, sessionCreatedAt: Date, data: SendMessageJobData): Promise<string> {
    const queue = this.getOrCreateQueue(sessionId, sessionCreatedAt);
    const job = await queue.add("send-message", data, {
      // O delay real de processamento humano/orgânico é aplicado no worker
      // (ver QueueWorker), este é só o enfileiramento.
    });
    return job.id ?? "";
  }

  async clear(sessionId: string): Promise<void> {
    const queue = this.queues.get(sessionId);
    if (!queue) return;
    await queue.drain();
  }

  async getQueueSize(sessionId: string): Promise<number> {
    const queue = this.queues.get(sessionId);
    if (!queue) return 0;
    return queue.count();
  }
}

