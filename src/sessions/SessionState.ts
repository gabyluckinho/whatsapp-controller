export enum SessionState {
  AGUARDANDO_QR = "AGUARDANDO_QR",
  CONECTANDO = "CONECTANDO",
  CONECTADO = "CONECTADO",
  DESCONECTADO = "DESCONECTADO",
  REINICIANDO = "REINICIANDO",
  PAUSADO = "PAUSADO",
  ERRO = "ERRO",
}

/** Transições permitidas — qualquer transição fora desta tabela deve ser rejeitada e logada como anomalia. */
export const ALLOWED_TRANSITIONS: Record<SessionState, SessionState[]> = {
  [SessionState.AGUARDANDO_QR]: [SessionState.CONECTANDO, SessionState.ERRO],
  [SessionState.CONECTANDO]: [SessionState.CONECTADO, SessionState.AGUARDANDO_QR, SessionState.ERRO],
  [SessionState.CONECTADO]: [SessionState.DESCONECTADO, SessionState.PAUSADO, SessionState.ERRO],
  [SessionState.DESCONECTADO]: [SessionState.REINICIANDO, SessionState.ERRO],
  [SessionState.REINICIANDO]: [SessionState.AGUARDANDO_QR, SessionState.CONECTANDO, SessionState.ERRO],
  [SessionState.PAUSADO]: [SessionState.CONECTADO, SessionState.REINICIANDO],
  [SessionState.ERRO]: [SessionState.REINICIANDO],
};

export function canTransition(from: SessionState, to: SessionState): boolean {
  return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
}

