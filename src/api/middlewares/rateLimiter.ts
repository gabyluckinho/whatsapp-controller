import rateLimit from "express-rate-limit";

/**
 * Rate limit na CAMADA DE API (proteção do próprio servidor contra abuso do
 * n8n/cliente). Não confundir com o rate limit orgânico da fila (QueueWorker),
 * que existe para proteger o NÚMERO de WhatsApp contra banimento — são
 * limites com propósitos diferentes e ambos são necessários.
 */
export const apiRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Muitas requisições. Tente novamente em instantes." },
});

/** Limite bem mais rígido para o login da Plataforma — protege contra força bruta na senha. */
export const platformLoginRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Muitas tentativas de login. Aguarde alguns minutos." },
});

