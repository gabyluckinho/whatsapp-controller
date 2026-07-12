import { describe, it, expect } from "vitest";
import { SessionState, canTransition } from "../../src/sessions/SessionState";

describe("SessionState transitions", () => {
  it("permite transição de AGUARDANDO_QR para CONECTANDO", () => {
    expect(canTransition(SessionState.AGUARDANDO_QR, SessionState.CONECTANDO)).toBe(true);
  });

  it("bloqueia transição direta de AGUARDANDO_QR para CONECTADO", () => {
    expect(canTransition(SessionState.AGUARDANDO_QR, SessionState.CONECTADO)).toBe(false);
  });

  it("permite reconexão de DESCONECTADO para REINICIANDO", () => {
    expect(canTransition(SessionState.DESCONECTADO, SessionState.REINICIANDO)).toBe(true);
  });

  it("bloqueia transição de PAUSADO direto para ERRO", () => {
    expect(canTransition(SessionState.PAUSADO, SessionState.ERRO)).toBe(false);
  });
});

