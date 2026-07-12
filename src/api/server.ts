import express from "express";
import path from "node:path";
import { env } from "../config/env";
import { SessionManager } from "../sessions/SessionManager";
import { LogRepository } from "../database/repositories/LogRepository";
import { apiKeyAuth } from "./middlewares/auth";
import { apiRateLimiter, platformLoginRateLimiter } from "./middlewares/rateLimiter";
import { errorHandler } from "./middlewares/errorHandler";
import { sessionsRouter } from "./routes/sessions.routes";
import { messagesRouter } from "./routes/messages.routes";
import { healthRouter } from "./routes/health.routes";
import { platformAuthRouter } from "./routes/platform.routes";
import { logger } from "../utils/logger";

export function createServer(sessionManager: SessionManager) {
  const app = express();
  const logRepository = new LogRepository();

  app.use(express.json({ limit: "10mb" }));

  app.get("/", (_req, res) => res.redirect("/platform"));

  // Sem auth por API key: healthcheck do Docker e login da Plataforma
  // (a Plataforma se autentica com sua própria senha, ver platform.routes.ts).
    app.use("/health", healthRouter(sessionManager));
  app.use("/platform/login", platformLoginRateLimiter, platformAuthRouter());

  // TEMPORÁRIO — remover depois de diagnosticar o problema de auth via query.
  // Sem autenticação nenhuma, só mostra exatamente o que o servidor recebeu.
   app.use("/health", healthRouter(sessionManager));
  app.use("/platform/login", platformLoginRateLimiter, platformAuthRouter());
    });
  });
  // Dashboard estático (HTML/JS puro) — servido pelo próprio Controller,
  // sem container/build separado. A autenticação acontece no próprio painel
  // (tela de login chama /platform/login e guarda a API key no navegador).
  app.use("/platform", express.static(path.join(__dirname, "..", "..", "public", "platform")));

  app.use(apiRateLimiter);
  app.use(apiKeyAuth);

  app.use("/sessions", sessionsRouter(sessionManager, logRepository));
  app.use("/sessions", messagesRouter(sessionManager));

  app.use(errorHandler);

  return app;
}

export function startServer(): void {
  const sessionManager = new SessionManager();

  sessionManager
    .initializeAll()
    .then(() => logger.info("SessionManager inicializado"))
    .catch((err) => logger.error({ err }, "Falha ao inicializar sessões"));

  const app = createServer(sessionManager);
  app.listen(env.PORT, () => {
    logger.info({ port: env.PORT }, "API interna no ar");
    logger.info({ url: `http://localhost:${env.PORT}/platform` }, "Plataforma (dashboard) disponível");
  });
}

