export interface SendTextParams {
  sessionId: string;
  contact: string;
  text: string;
}

export interface SendMediaParams {
  sessionId: string;
  contact: string;
  filePath: string;
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

  sendText(params: SendTextParams): Promise<void>;
  sendImage(params: SendMediaParams): Promise<void>;
  sendAudio(params: SendMediaParams): Promise<void>;
  sendDocument(params: SendMediaParams): Promise<void>;
  sendVideo(params: SendMediaParams): Promise<void>;

  onIncomingMessage(sessionId: string, handler: (msg: IncomingMessage) => void): void;
  onDisconnected(sessionId: string, handler: () => void): void;
}

