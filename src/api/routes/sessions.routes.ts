import { Router } from "express";
import { z } from "zod";
import { SessionManager } from "../../sessions/SessionManager";
import { LogRepository } from "../../database/repositories/LogRepository";

const createSessionSchema = z.object({
  id: z
    .string()
    .min(1)
    .max(20)
    .regex(/^[a-zA-Z0-9_-]+$/, "id deve conter apenas letras, números, hífen ou underscore"),
  name: z.string().min(1).max(80),
});

export function sessionsRouter(sessionManager: SessionManager, logRepository: LogRepository): Router {
  const router = Router();

  router.get("/", (_req, res) => {
    const sessions = sessionManager.list().map((s) => ({
      id: s.sessionId,
      name: s.sessionName,
      status: s.getState(),
      createdAt: s.getCreatedAt(),
    }));
    res.json({ sessions });
  });

  // Usado pela Plataforma para adicionar um número novo em tempo real,
  // sem redeploy: cria o registro no Supabase, sobe o supervisor e o
  // worker da fila, e o QR code fica disponível em segundos.
  router.post("/", async (req, res) => {
    const parsed = createSessionSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    try {
      const supervisor = await sessionManager.addSession(parsed.data.id, parsed.data.name);
      res.status(201).json({ id: supervisor.sessionId, name: supervisor.sessionName, status: supervisor.getState() });
    } catch (error) {
      res.status(409).json({ error: error instanceof Error ? error.message : "Falha ao criar sessão" });
    }
  });

  router.delete("/:id", async (req, res) => {
    try {
      await sessionManager.removeSession(req.params.id);
      res.status(200).json({ message: "Sessão removida" });
    } catch (error) {
      res.status(404).json({ error: error instanceof Error ? error.message : "Sessão não encontrada" });
    }
  });

  router.get("/:id/status", (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    res.json({ id: supervisor.sessionId, status: supervisor.getState() });
  });

  router.get("/:id/qrcode", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    const qr = await sessionManager.getQrCode(supervisor.sessionId);
    res.json({ id: supervisor.sessionId, status: supervisor.getState(), qrCode: qr });
  });

  router.post("/:id/restart", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await supervisor.restart();
    res.status(202).json({ message: "Reinício solicitado" });
  });

  router.post("/:id/pause", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await supervisor.pause();
    res.status(200).json({ message: "Sessão pausada" });
  });

  router.post("/:id/resume", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await supervisor.resume();
    res.status(200).json({ message: "Sessão retomada" });
  });

  router.get("/:id/logs", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    const logs = await logRepository.listRecent(supervisor.sessionId);
    res.json({ logs });
  });

  return router;
}

