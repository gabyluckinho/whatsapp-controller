import { Router } from "express";
import { z } from "zod";
import { env } from "../../config/env";
import { logger } from "../../utils/logger";

const loginSchema = z.object({ password: z.string().min(1) });

/**
 * Login simples da Plataforma (dashboard administrativo). É intencionalmente
 * separado da API_KEY usada pelo n8n: a senha do painel (PLATFORM_ADMIN_PASSWORD)
 * é o que um humano digita; depois de validada, devolvemos a própria API_KEY
 * para o navegador guardar (localStorage) e usar nas chamadas seguintes às
 * mesmas rotas /sessions que o n8n usa — um único mecanismo de autorização
 * de API, duas portas de entrada (humano via senha, n8n via API key direta).
 */
export function platformAuthRouter(): Router {
  const router = Router();

  router.post("/login", (req, res) => {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "Senha ausente" });
      return;
    }

    if (parsed.data.password !== env.PLATFORM_ADMIN_PASSWORD) {
      logger.warn({ ip: req.ip }, "Tentativa de login na Plataforma com senha incorreta");
      res.status(401).json({ error: "Senha incorreta" });
      return;
    }

    res.json({ apiKey: env.API_KEY });
  });

  return router;
}

