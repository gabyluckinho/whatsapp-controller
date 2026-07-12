import { Router } from "express";
import { z } from "zod";
import { SessionManager } from "../../sessions/SessionManager";

const textSchema = z.object({ contact: z.string().min(3), text: z.string().min(1) });
const mediaSchema = z.object({ contact: z.string().min(3), filePath: z.string().min(1), caption: z.string().optional() });

export function messagesRouter(sessionManager: SessionManager): Router {
  const router = Router();
  const queueManager = sessionManager.getQueueManager();

  async function enqueue(
    req: any,
    res: any,
    type: "text" | "image" | "audio" | "document" | "video",
    schema: z.ZodTypeAny
  ) {
    const supervisor = sessionManager.requireSession(req.params.id);
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }

    const { contact, ...rest } = parsed.data;
    const jobId = await queueManager.enqueue(supervisor.sessionId, supervisor.getCreatedAt(), {
      sessionId: supervisor.sessionId,
      contact,
      type,
      payload: rest,
    });

    res.status(202).json({ jobId, queued: true });
  }

  router.post("/:id/messages/text", (req, res) => enqueue(req, res, "text", textSchema));
  router.post("/:id/messages/image", (req, res) => enqueue(req, res, "image", mediaSchema));
  router.post("/:id/messages/audio", (req, res) => enqueue(req, res, "audio", mediaSchema));
  router.post("/:id/messages/document", (req, res) => enqueue(req, res, "document", mediaSchema));
  router.post("/:id/messages/video", (req, res) => enqueue(req, res, "video", mediaSchema));

  router.post("/:id/queue/clear", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await queueManager.clear(supervisor.sessionId);
    res.json({ message: "Fila limpa" });
  });

  return router;
}

