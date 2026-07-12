export interface SendTextParams {
  sessionId: string;
  contact: string;
  text: string;
}

export interface SendMediaParams {
  sessionId: string;
  contact: string;
  /** Caminho de um arquivo já salvo no disco do Controller. */
  filePath?: string;
  /** URL pública do arquivo (ex: link do S3) — o Controller baixa antes de enviar. */
  mediaUrl?: string;
  caption?: string;
}

export interface IncomingMessage {
  contact: string;
  type: "text" | "image" | "audio" | "document" | "video" | "other";
  content: string;
  timestamp: string;
}

/**
 * Interface que abstrai o navegador. Permite testar SessionSupervisor e
 * QueueWorker com um driver fake, sem precisar de um Chromium real rodando.
 */
export interface IBrowserDriver {
  startSession(sessionId: string): Promise<void>;
  stopSession(sessionId: string): Promise<void>;
  getQrCode(sessionId: string): Promise<string | null>;
  isConnected(sessionId: string): Promise<boolean>;

  /**
   * Solicita o código de pareamento por número de telefone (alternativa ao QR).
   * phoneNumber deve vir só com dígitos, incluindo código do país (ex: 5511999999999).
   * Retorna o código de 8 caracteres que o usuário digita no celular.
   */
  requestPairingCode(sessionId: string, phoneNumber: string): Promise<string>;

  /** Caminho do último screenshot de erro capturado (pode não existir ainda). */
  getDebugScreenshotPath(sessionId: string): string;

  /** Caminho do HTML real da área de composição de mensagem no momento do erro. */
  getDebugHtmlPath(sessionId: string): string;

  sendText(params: SendTextParams): Promise<void>;
  sendImage(params: SendMediaParams): Promise<void>;
  sendAudio(params: SendMediaParams): Promise<void>;
  sendDocument(params: SendMediaParams): Promise<void>;
  sendVideo(params: SendMediaParams): Promise<void>;

  onIncomingMessage(sessionId: string, handler: (msg: IncomingMessage) => void): void;
  onDisconnected(sessionId: string, handler: () => void): void;
}
