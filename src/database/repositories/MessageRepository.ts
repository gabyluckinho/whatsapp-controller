import { supabase } from "../supabaseClient";
import { logger } from "../../utils/logger";

export class MessageRepository {
  async recordSent(sessionId: string, contact: string, type: string, status: "success" | "error"): Promise<void> {
    const { error } = await supabase.from("messages").insert({
      session_id: sessionId,
      direction: "out",
      contact,
      type,
      status,
      sent_at: new Date().toISOString(),
    });
    if (error) logger.error({ error, sessionId }, "Falha ao registrar mensagem enviada");
  }

  async recordReceived(sessionId: string, contact: string, type: string, content: string): Promise<void> {
    const { error } = await supabase.from("messages").insert({
      session_id: sessionId,
      direction: "in",
      contact,
      type,
      content_ref: content,
      status: "received",
      received_at: new Date().toISOString(),
    });
    if (error) logger.error({ error, sessionId }, "Falha ao registrar mensagem recebida");
  }
}

