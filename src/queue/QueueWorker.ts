import { Worker, Job, ConnectionOptions } from "bullmq";
import { env } from "../config/env";
import { SendMessageJobData } from "./QueueManager";
import { IBrowserDriver } from "../playwright/BrowserDriver";
import { WebhookDispatcher } from "../webhooks/WebhookDispatcher";
import { LogRepository } from "../database/repositories/LogRepository";
import { MessageRepository } from "../database/repositories/MessageRepository";
import { computeMinIntervalMs, sleep } from "../utils/humanBehavior";
import { childLogger } from "../utils/logger";

/**
 * Um worker por sessão, com `concurrency: 1` — garante que NUNCA duas
 * mensagens da mesma sessão sejam processadas ao mesmo tempo (requisito
 * de negócio) e, junto com o delay mínimo dinâmico, mantém o volume de
 * envio dentro de um padrão que se assemelha a uso humano.
 */
export function createSessionWorker(
  sessionId: string,
  sessionCreatedAt: Date,
  driver: IBrowserDriver,
  webhookDispatcher: WebhookDispatcher,
  logRepository: LogRepository,
  messageRepository: MessageRepository
): Worker<SendMessageJobData> {
  const log = childLogger(sessionId);

  const connection: ConnectionOptions = {
    host: env.REDIS_HOST,
    port: env.REDIS_PORT,
    password: env.REDIS_PASSWORD || undefined,
    maxRetriesPerRequest: null,
  };

  const worker = new Worker<SendMessageJobData>(
    `session:${sessionId}`,
    async (job: Job<SendMessageJobData>) => {
      const { contact, type, payload } = job.data;

      // Respiro mínimo antes de processar o próximo job — mesmo que a fila
      // esteja cheia, isso impede rajadas de mensagens em sequência.
      const minInterval = computeMinIntervalMs(sessionCreatedAt);
      await sleep(minInterval);

      try {
        switch (type) {
          case "text":
            await driver.sendText({ sessionId, contact, text: payload.text as string });
            break;
          case "image":
            await driver.sendImage({ sessionId, contact, filePath: payload.filePath as string, caption: payload.caption as string | undefined });
            break;
          case "audio":
            await driver.sendAudio({ sessionId, contact, filePath: payload.filePath as string });
            break;
          case "document":
            await driver.sendDocument({ sessionId, contact, filePath: payload.filePath as string, caption: payload.caption as string | undefined });
            break;
          case "video":
            await driver.sendVideo({ sessionId, contact, filePath: payload.filePath as string, caption: payload.caption as string | undefined });
            break;
        }

        await messageRepository.recordSent(sessionId, contact, type, "success");
        await webhookDispatcher.emit("message.sent", { sessionId, jobId: job.id, contact, type, status: "success" });
      } catch (error) {
        log.error({ error, jobId: job.id }, "Falha ao processar job de envio");
        await messageRepository.recordSent(sessionId, contact, type, "error");
        await logRepository.record(sessionId, "error", "send_failed", String(error));
        await webhookDispatcher.emit("message.sent", { sessionId, jobId: job.id, contact, type, status: "error" });
        throw error; // deixa o BullMQ aplicar o retry configurado na fila
      }
    },
    {
      connection,
      concurrency: 1, // trava dura: nunca 2 mensagens simultâneas na mesma sessão
      limiter: {
        max: 1,
        duration: computeMinIntervalMs(sessionCreatedAt),
      },
    }
  );

  worker.on("failed", (job, err) => {
    log.error({ jobId: job?.id, err }, "Job falhou definitivamente após retries");
  });

  return worker;
}

