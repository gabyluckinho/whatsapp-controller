/**
 * Seletores do DOM do WhatsApp Web isolados neste arquivo porque o WhatsApp
 * troca classes/atributos com frequência. Quando algo parar de funcionar,
 * o primeiro lugar a checar é este arquivo — normalmente é só um seletor
 * desatualizado, não um bug de lógica.
 *
 * Preferir sempre atributos data-testid / aria-label (mais estáveis) a
 * classes CSS geradas (menos estáveis).
 */
export const WhatsAppSelectors = {
  qrCodeCanvas: 'canvas[aria-label="Scan this QR code to link a device!"]',
  // IMPORTANTE: 'div[id="app"]' existe tanto logado quanto na tela de QR —
  // não serve pra detectar "conectado". Usamos a barra lateral de conversas
  // (só existe depois do login real) como sinal de conexão confirmada.
  loggedInIndicator: '#pane-side, div[aria-label="Chat list"]',
  chatSearchInput: 'div[contenteditable="true"][data-tab="3"], div[aria-label="Search input textbox"]',
  messageInput: 'div[contenteditable="true"][data-tab="10"], footer div[contenteditable="true"]',
  sendButton: 'button[aria-label="Send"]',
  attachButton: 'div[title="Attach"], button[aria-label="Attach"]',
  attachImageInput: 'input[accept*="image"]',
  attachDocumentInput: 'input[accept*="*"]',
  incomingMessageBubble: 'div[data-testid="msg-container"], div.message-in',
  disconnectedBanner: 'div[data-testid="alert-phone"], div[data-ref]',
} as const;
