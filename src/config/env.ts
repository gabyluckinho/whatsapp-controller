import dotenv from "dotenv";
import { z } from "zod";

dotenv.config();

const envSchema = z.object({
  PORT: z.coerce.number().default(3000),
  API_KEY: z.string().min(16, "API_KEY deve ter pelo menos 16 caracteres"),
  NODE_ENV: z.enum(["development", "production", "test"]).default("production"),

  REDIS_HOST: z.string().default("redis"),
  REDIS_PORT: z.coerce.number().default(6379),
  REDIS_PASSWORD: z.string().optional().default(""),

  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(10),

  N8N_WEBHOOK_URL: z.string().url(),
  N8N_WEBHOOK_SECRET: z.string().min(8),

  SESSIONS: z.string().optional().default(""),

    PLATFORM_ADMIN_PASSWORD: z.string().min(8, "PLATFORM_ADMIN_PASSWORD deve ter pelo menos 8 caracteres"),

  // Número (com código do país, só dígitos) que recebe aviso via WhatsApp
  // quando qualquer sessão desconecta. Deixe em branco para desativar.
  ADMIN_NOTIFICATION_PHONE: z.string().optional().default(""),

  HUMAN_DELAY_MIN_MS: z.coerce.number().default(1800),
  HUMAN_DELAY_MAX_MS: z.coerce.number().default(6500),
  MAX_MESSAGES_PER_MINUTE: z.coerce.number().default(8),
  WARMUP_PERIOD_HOURS: z.coerce.number().default(48),
  WARMUP_MAX_MESSAGES_PER_MINUTE: z.coerce.number().default(2),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error("Variáveis de ambiente inválidas:", parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;

export type SessionDefinition = {
  id: string;
  name: string;
};

/**
 * Parseia a variável SESSIONS (ex: "01,Vendas;02,Suporte") em uma lista tipada.
 * Este é o único lugar que precisa mudar para ir de 3 para 30/50 sessões:
 * basta editar a variável de ambiente, sem tocar em código.
 */
export function parseSessionDefinitions(raw: string): SessionDefinition[] {
  if (!raw.trim()) return [];
  return raw
    .split(";")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [id, name] = entry.split(",").map((part) => part.trim());
      if (!id || !name) {
        throw new Error(`Entrada inválida em SESSIONS: "${entry}". Formato esperado "id,nome".`);
      }
      return { id, name };
    });
}

/**
 * Semente OPCIONAL para o primeiro boot (ex: "01,Vendas;02,Suporte"). Só é
 * usada se a tabela `sessions` no Supabase estiver vazia — depois disso, a
 * fonte de verdade é o banco, gerenciado pela Plataforma (dashboard) via
 * SessionManager.addSession/removeSession. Pode ficar em branco.
 */
export const sessionDefinitions = parseSessionDefinitions(env.SESSIONS);

