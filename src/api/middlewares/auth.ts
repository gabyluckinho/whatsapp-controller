import { Request, Response, NextFunction } from "express";
import { env } from "../../config/env";

export function apiKeyAuth(req: Request, res: Response, next: NextFunction): void {
  // Aceita a chave no header (uso normal via n8n/API) OU na URL como
  // ?apiKey=... — necessário pra abrir links como o screenshot de debug
  // direto no navegador, já que uma navegação simples não envia headers.
  const key = req.header("x-api-key") || (req.query.apiKey as string | undefined);
  if (!key || key !== env.API_KEY) {
    res.status(401).json({ error: "API key ausente ou inválida" });
    return;
  }
  next();
}
