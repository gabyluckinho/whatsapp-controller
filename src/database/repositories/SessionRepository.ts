import { supabase } from "../supabaseClient";
import { logger } from "../../utils/logger";

export interface SessionRecord {
  id: string;
  name: string;
  phone_number: string | null;
  status: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

/**
 * Fonte da verdade sobre QUAIS sessões existem. Antes, essa lista vinha fixa
 * da variável de ambiente SESSIONS — qualquer número novo exigia redeploy.
 * Agora a Plataforma (dashboard) cria/remove registros aqui, e o
 * SessionManager lê esta tabela na inicialização e reage a mudanças em
 * tempo real via os métodos addSession/removeSession.
 */
export class SessionRepository {
  async listActive(): Promise<SessionRecord[]> {
    const { data, error } = await supabase.from("sessions").select("*").eq("active", true).order("created_at");
    if (error) {
      logger.error({ error }, "Falha ao listar sessões ativas no Supabase");
      return [];
    }
    return data as SessionRecord[];
  }

  async create(id: string, name: string): Promise<void> {
    const { error } = await supabase.from("sessions").insert({ id, name, status: "AGUARDANDO_QR", active: true });
    if (error) throw new Error(`Falha ao criar sessão no banco: ${error.message}`);
  }

  async updateStatus(id: string, status: string): Promise<void> {
    const { error } = await supabase
      .from("sessions")
      .update({ status, updated_at: new Date().toISOString() })
      .eq("id", id);
    if (error) logger.error({ error, id }, "Falha ao atualizar status da sessão no Supabase");
  }

  async updatePhoneNumber(id: string, phoneNumber: string): Promise<void> {
    const { error } = await supabase.from("sessions").update({ phone_number: phoneNumber }).eq("id", id);
    if (error) logger.error({ error, id }, "Falha ao atualizar número da sessão");
  }

  async deactivate(id: string): Promise<void> {
    const { error } = await supabase.from("sessions").update({ active: false }).eq("id", id);
    if (error) throw new Error(`Falha ao desativar sessão no banco: ${error.message}`);
  }

  async exists(id: string): Promise<boolean> {
    const { data, error } = await supabase.from("sessions").select("id").eq("id", id).maybeSingle();
    if (error) {
      logger.error({ error, id }, "Falha ao checar existência da sessão");
      return false;
    }
    return !!data;
  }
}

