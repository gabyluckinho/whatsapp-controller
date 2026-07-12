import { Request, Response, NextFunction } from "express";
import { env } from "../../config/env";

export function apiKeyAuth(req: Request, res: Response, next: NextFunction): void {
  const key = req.header("x-api-key");
  if (!key || key !== env.API_KEY) {
    res.status(401).json({ error: "API key ausente ou inválida" });
    return;
  }
  next();
}

