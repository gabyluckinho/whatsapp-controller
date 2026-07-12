import { Router } from "express";
import { SessionManager } from "../../sessions/SessionManager";

export function healthRouter(sessionManager: SessionManager): Router {
  const router = Router();

  router.get("/", (_req, res) => {
    const sessions = sessionManager.list().map((s) => ({ id: s.sessionId, status: s.getState() }));
    res.json({ status: "ok", uptime: process.uptime(), sessions });
  });

  return router;
}
