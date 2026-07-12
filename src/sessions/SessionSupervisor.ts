import { IBrowserDriver, IncomingMessage } from "../playwright/BrowserDriver";
import { SessionState, canTransition } from "./SessionState";
import { RECONNECT_BACKOFF_MS } from "../config/constants";
import { childLogger } from "../utils/logger";
import { LogRepository } from "../database/repositories/LogRepository";
import { MessageRepository } from "../database/repositories/MessageRepository";
import { SessionRepository } from "../database/repositories/SessionRepository";
import { WebhookDispatcher } from "../webhooks/WebhookDispatcher";

/**
 * Supervisiona o ciclo de vida completo de UMA sessão: start, stop, restart,
 * detecção de desconexão e reconexão com backoff. Cada instância desta classe
 * é isolada — uma falha aqui nunca deve propagar para outra sessão, e é por
 * isso que o SessionManager cria uma instância por sessão, cada uma com seu
 * próprio catch/try e próprio ciclo, sem estado compartilhado entre elas.
 */
export class SessionSupervisor {
  private state: SessionState = SessionState.AGUARDANDO_QR;
  private reconnectAttempt = 0;
  private readonly log;
  private createdAt = new Date();

  constructor(
    public readonly sessionId: string,
    public readonly sessionName: string,
    private readonly driver: IBrowserDriver,
    private readonly logRepository: LogRepository,
    private readonly webhookDispatcher: WebhookDispatcher,
    private readonly messageRepository: MessageRepository,
    private readonly sessionRepository: SessionRepository,
    private readonly onDisconnectNotify?: (sessionId: string, sessionName: string, newState: SessionState) => void
  ) {
    this.log = childLogger(sessionId);
  }

  getState(): SessionState {
    return this.state;
  }

  getCreatedAt(): Date {
    return this.createdAt;
  }

  private async setState(next: SessionState): Promise<void> {
    if (!canTransition(this.state, next)) {
      this.log.warn({ from: this.state, to: next }, "Transição de estado não permitida, ignorando");
      return;
    }
    const previous = this.state;
    this.state = next;
    await this.logRepository.record(this.sessionId, "info", "state_changed", `${previous} -> ${next}`);
    await this.sessionRepository.updateStatus(this.sessionId, next);
    await this.webhookDispatcher.emit("session.status_changed", {
      sessionId: this.sessionId,
      status: next,
    });

    // Dispara o aviso de notificação (WhatsApp pro admin) sempre que a sessão
    // cai por qualquer motivo — desconexão real ou falha ao iniciar/reconectar.
    if (next === SessionState.DESCONECTADO || next === SessionState.ERRO) {
      this.onDisconnectNotify?.(this.sessionId, this.sessionName, next);
    }
  }

  async start(): Promise<void> {
    try {
      await this.setState(SessionState.CONECTANDO);
      await this.driver.startSession(this.sessionId);

      this.driver.onDisconnected(this.sessionId, () => this.handleDisconnection());
      this.driver.onIncomingMessage(this.sessionId, (msg) => this.handleIncomingMessage(msg));

      const connected = await this.driver.isConnected(this.sessionId);
      await this.setState(connected ? SessionState.CONECTADO : SessionState.AGUARDANDO_QR);
      this.reconnectAttempt = 0;
    } catch (error) {
      this.log.error({ error }, "Falha ao iniciar sessão");
      await this.setState(SessionState.ERRO);
      await this.logRepository.record(this.sessionId, "error", "start_failed", String(error));
      await this.scheduleReconnect();
    }
  }

  async stop(): Promise<void> {
    await this.driver.stopSession(this.sessionId);
  }

  async restart(): Promise<void> {
    await this.setState(SessionState.REINICIANDO);
    await this.driver.stopSession(this.sessionId);
    await this.start();
  }

  async pause(): Promise<void> {
    await this.setState(SessionState.PAUSADO);
  }

  async resume(): Promise<void> {
    await this.setState(SessionState.CONECTADO);
  }

  private async handleDisconnection(): Promise<void> {
    this.log.warn("Sessão desconectada, agendando reconexão");
    await this.setState(SessionState.DESCONECTADO);
    await this.logRepository.record(this.sessionId, "warn", "disconnected", "Sessão perdeu conexão");
    await this.scheduleReconnect();
  }

  private async scheduleReconnect(): Promise<void> {
    const delay = RECONNECT_BACKOFF_MS[Math.min(this.reconnectAttempt, RECONNECT_BACKOFF_MS.length - 1)];
    this.reconnectAttempt++;
    this.log.info({ delay, attempt: this.reconnectAttempt }, "Reagendando reconexão");
    setTimeout(() => {
      this.restart().catch((err) => this.log.error({ err }, "Falha na tentativa de reconexão"));
    }, delay);
  }

  private async handleIncomingMessage(msg: IncomingMessage): Promise<void> {
    await this.logRepository.record(this.sessionId, "info", "message_received", msg.content);
    await this.messageRepository.recordReceived(this.sessionId, msg.contact, msg.type, msg.content);
    await this.webhookDispatcher.emit("message.received", {
      sessionId: this.sessionId,
      ...msg,
    });
  }
}
