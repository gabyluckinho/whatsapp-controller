import { supabase } from "../supabaseClient";
import { logger } from "../../utils/logger";

export class LogRepository {
  async record(sessionId: string, level: "info" | "warn" | "error", event: string, message: string): Promise<void> {
    const { error } = await supabase.from("logs").insert({
      session_id: sessionId,
      level,
      event,
      message,
    });

    if (error) {
      // Nunca deixar falha de log derrubar o fluxo principal — apenas loga localmente.
      logger.error({ error, sessionId, event }, "Falha ao gravar log no Supabase");
    }
  }

  async listRecent(sessionId: string, limit = 100) {
    const { data, error } = await supabase
      .from("logs")
      .select("*")
      .eq("session_id", sessionId)
      .order("created_at", { ascending: false })
      .limit(limit);

    if (error) {
      logger.error({ error, sessionId }, "Falha ao listar logs");
      return [];
    }
    return data;
  }
}

