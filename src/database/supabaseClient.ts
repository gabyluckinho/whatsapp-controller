import { createClient } from "@supabase/supabase-js";
import WebSocket from "ws";
import { env } from "../config/env";

/**
 * O Node 20 (usado na imagem do Controller) não expõe WebSocket nativo por
 * padrão, e a lib do Supabase falha ao inicializar por causa disso — mesmo
 * sem usarmos o recurso de "realtime" do Supabase. Passar o pacote `ws`
 * explicitamente resolve, sem precisar trocar a versão do Node.
 */
export const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
  realtime: {
    transport: WebSocket as never,
  },
});
