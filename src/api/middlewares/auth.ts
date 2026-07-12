import { Request, Response, NextFunction } from "express";
import { env } from "../../config/env";
import { logger } from "../../utils/logger";

export function apiKeyAuth(req: Request, res: Response, next: NextFunction): void {
  const key = req.header("x-api-key") || (req.query.apiKey as string | undefined);

  // TEMPORÁRIO — log de diagnóstico, remover depois de resolver.
  logger.info(
    {
      path: req.path,
      hasHeaderKey: !!req.header("x-api-key"),
      hasQueryKey: !!req.query.apiKey,
      keyReceived: key ? `${key.slice(0, 4)}...${key.slice(-4)}` : null,
      matches: key === env.API_KEY,
    },
    "DEBUG apiKeyAuth"
  );

  if (!key || key !== env.API_KEY) {
    res.status(401).json({ error: "API key ausente ou inválida" });
    return;
  }
  next();
}
