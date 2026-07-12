import { env } from "../config/env";
import { withRetry } from "../utils/retry";
import { logger } from "../utils/logger";

type EventName =
  | "session.status_changed"
  | "message.received"
  | "message.sent"
  | "session.qr_updated"
  | "session.error";

/**
 * Envia eventos para o webhook do n8n. Se o n8n estiver fora do ar, os eventos
 * pendentes ficam em uma fila em memória simples e são reenviados em segundo
 * plano — para volume alto/produção crítica, trocar por uma fila Redis dedicada
 * (mesmo padrão do QueueManager), mas para o MVP isso já evita perda de eventos
 * em quedas curtas do n8n.
 */
export class WebhookDispatcher {
  private pending: Array<{ event: EventName; payload: unknown; attempts: number }> = [];
  private flushing = false;

  async emit(event: EventName, payload: unknown): Promise<void> {
    try {
      await withRetry(() => this.send(event, payload), {
        attempts: 3,
        baseDelayMs: 1000,
        onRetry: (err, attempt) => logger.warn({ err, attempt, event }, "Retry ao enviar webhook"),
      });
    } catch (error) {
      logger.error({ error, event }, "Falha definitiva ao enviar webhook, guardando para retry posterior");
      this.pending.push({ event, payload, attempts: 0 });
      this.scheduleFlush();
    }
  }

  private async send(event: EventName, payload: unknown): Promise<void> {
    const response = await fetch(env.N8N_WEBHOOK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Webhook-Secret": env.N8N_WEBHOOK_SECRET,
      },
      body: JSON.stringify({ event, payload, emittedAt: new Date().toISOString() }),
    });

    if (!response.ok) {
      throw new Error(`Webhook respondeu com status ${response.status}`);
    }
  }

  private scheduleFlush(): void {
    if (this.flushing) return;
    this.flushing = true;
    setTimeout(async () => {
      await this.flushPending();
      this.flushing = false;
      if (this.pending.length > 0) this.scheduleFlush();
    }, 15_000);
  }

  private async flushPending(): Promise<void> {
    const batch = [...this.pending];
    this.pending = [];
    for (const item of batch) {
      try {
        await this.send(item.event, item.payload);
      } catch {
        item.attempts++;
        if (item.attempts < 5) this.pending.push(item);
        else logger.error({ item }, "Evento de webhook descartado após múltiplas falhas");
      }
    }
  }
}

