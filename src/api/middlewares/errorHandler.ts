import { Request, Response, NextFunction } from "express";
import { logger } from "../../utils/logger";

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction): void {
  logger.error({ err, path: req.path }, "Erro não tratado na API");
  const message = err instanceof Error ? err.message : "Erro interno";
  res.status(500).json({ error: message });
}

