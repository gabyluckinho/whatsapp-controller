import { Router } from "express";
import { z } from "zod";
import { SessionManager } from "../../sessions/SessionManager";
import { asyncHandler } from "../middlewares/asyncHandler";

const textSchema = z.object({ contact: z.string().min(3), text: z.string().min(1) });
const mediaSchema = z
  .object({
    contact: z.string().min(3),
    filePath: z.string().min(1).optional(),
    mediaUrl: z.string().url().optional(),
    caption: z.string().optional(),
  })
  .refine((data) => data.filePath || data.mediaUrl, {
    message: "Informe filePath (arquivo local) ou mediaUrl (link público, ex: S3)",
  });

export function messagesRouter(sessionManager: SessionManager): Router {
  const router = Router();
  const queueManager = sessionManager.getQueueManager();

  function enqueue(type: "text" | "image" | "audio" | "document" | "video", schema: z.ZodTypeAny) {
    return asyncHandler(async (req, res) => {
      let supervisor;
      try {
        supervisor = sessionManager.requireSession(req.params.id);
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
        return;
      }

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
    });
  }

  router.post("/:id/messages/text", enqueue("text", textSchema));
  router.post("/:id/messages/image", enqueue("image", mediaSchema));
  router.post("/:id/messages/audio", enqueue("audio", mediaSchema));
  router.post("/:id/messages/document", enqueue("document", mediaSchema));
  router.post("/:id/messages/video", enqueue("video", mediaSchema));

  router.post(
    "/:id/queue/clear",
    asyncHandler(async (req, res) => {
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        await queueManager.clear(supervisor.sessionId);
        res.json({ message: "Fila limpa" });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  return router;
}
