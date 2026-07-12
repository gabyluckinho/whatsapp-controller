import { Router } from "express";
import { z } from "zod";
import fs from "node:fs/promises";
import { SessionManager } from "../../sessions/SessionManager";
import { LogRepository } from "../../database/repositories/LogRepository";
import { asyncHandler } from "../middlewares/asyncHandler";

const createSessionSchema = z.object({
  id: z
    .string()
    .min(1)
    .max(20)
    .regex(/^[a-zA-Z0-9_-]+$/, "id deve conter apenas letras, números, hífen ou underscore"),
  name: z.string().min(1).max(80),
});

const pairingCodeSchema = z.object({
  phoneNumber: z.string().min(10, "Inclua o código do país, ex: 5511999999999"),
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

  router.post(
    "/",
    asyncHandler(async (req, res) => {
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
    })
  );

  router.delete(
    "/:id",
    asyncHandler(async (req, res) => {
      try {
        await sessionManager.removeSession(req.params.id);
        res.status(200).json({ message: "Sessão removida" });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : "Sessão não encontrada" });
      }
    })
  );

  router.get(
    "/:id/status",
    asyncHandler(async (req, res) => {
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        res.json({ id: supervisor.sessionId, status: supervisor.getState() });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  router.get(
    "/:id/qrcode",
    asyncHandler(async (req, res) => {
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        const qr = await sessionManager.getQrCode(supervisor.sessionId);
        res.json({ id: supervisor.sessionId, status: supervisor.getState(), qrCode: qr });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  router.post(
    "/:id/pairing-code",
    asyncHandler(async (req, res) => {
      const parsed = pairingCodeSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: parsed.error.flatten() });
        return;
      }
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        const code = await sessionManager.requestPairingCode(supervisor.sessionId, parsed.data.phoneNumber);
        res.json({ code });
      } catch (error) {
        res.status(422).json({ error: error instanceof Error ? error.message : "Falha ao gerar código de pareamento" });
      }
    })
  );

  router.post(
    "/:id/restart",
    asyncHandler(async (req, res) => {
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        await supervisor.restart();
        res.status(202).json({ message: "Reinício solicitado" });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  router.post(
    "/:id/pause",
    asyncHandler(async (req, res) => {
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        await supervisor.pause();
        res.status(200).json({ message: "Sessão pausada" });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  router.post(
    "/:id/resume",
    asyncHandler(async (req, res) => {
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        await supervisor.resume();
        res.status(200).json({ message: "Sessão retomada" });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  router.get(
    "/:id/logs",
    asyncHandler(async (req, res) => {
      try {
        const supervisor = sessionManager.requireSession(req.params.id);
        const logs = await logRepository.listRecent(supervisor.sessionId);
        res.json({ logs });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  // Mostra o print da tela exata do momento da última falha de envio —
  // útil pra depurar seletores do WhatsApp Web sem acesso visual direto
  // ao navegador headless. Abre direto no navegador como imagem.
  router.get(
    "/:id/debug-screenshot",
    asyncHandler(async (req, res) => {
      try {
        const screenshotPath = sessionManager.getDebugScreenshotPath(req.params.id);
        res.sendFile(screenshotPath, (err) => {
          if (err) {
            res.status(404).json({ error: "Nenhum screenshot de erro disponível ainda para essa sessão" });
          }
        });
      } catch (error) {
        res.status(404).json({ error: error instanceof Error ? error.message : `Sessão "${req.params.id}" não encontrada` });
      }
    })
  );

  // Mostra o HTML real da área de composição de mensagem no momento do
  // último erro — mais preciso que o screenshot pra corrigir seletores,
  // já que mostra os atributos/estrutura reais, não só a aparência visual.
  // Lê o arquivo manualmente (em vez de sendFile) pra garantir texto puro —
  // sendFile serviria como text/html e o navegador tentaria renderizar a
  // página em vez de mostrar o código como texto.
  router.get(
    "/:id/debug-html",
    asyncHandler(async (req, res) => {
      try {
        const htmlPath = sessionManager.getDebugHtmlPath(req.params.id);
        const content = await fs.readFile(htmlPath, "utf-8");
        res.type("text/plain").send(content);
      } catch (error) {
        res.status(404).json({ error: "Nenhum HTML de erro disponível ainda para essa sessão" });
      }
    })
  );

  return router;
}
