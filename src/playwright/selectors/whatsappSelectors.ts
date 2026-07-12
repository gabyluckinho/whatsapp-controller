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
  loggedInIndicator: '#pane-side, div[aria-label="Chat list"]',
  chatSearchInput:
    '#side div[contenteditable="true"][data-lexical-editor="true"], #side input[type="text"], #side div[contenteditable="true"], #pane-side div[contenteditable="true"], div[contenteditable="true"][data-tab="3"]',
  messageInput:
    'footer div[contenteditable="true"][data-lexical-editor="true"], footer div[contenteditable="true"], #main div[contenteditable="true"][data-lexical-editor="true"], #main footer div[contenteditable="true"], div[contenteditable="true"][data-tab="10"]',
  sendButton:
    'button[aria-label="Send"], button[aria-label="Enviar"], [aria-label*="Enviar" i], [aria-label*="Send" i], [data-icon="send"], [data-icon*="send" i], div[role="button"][data-icon], span[data-icon][role="button"]',
  attachButton: 'div[title="Attach"], div[title="Anexar"], button[aria-label="Attach"], button[aria-label="Anexar"], [data-icon="attach"], [data-icon="plus"]',
  attachImageInput: 'input[accept*="image"]',
  attachDocumentInput: 'input[accept*="*"]',
  incomingMessageBubble: 'div[data-testid="msg-container"], div.message-in',
  disconnectedBanner: 'div[data-testid="alert-phone"], div[data-ref]',

  // Presente quando o contato bloqueou esse número — o WhatsApp mostra essa
  // barra ("Apagar conversa" / "Desbloquear") no lugar da caixa normal de
  // mensagem. Detectar isso cedo evita 30s de timeout tentando clicar em
  // algo que não existe, e dá um erro claro em vez de um genérico.
  blockedContactIndicator: '[data-testid="settings-blocked"]',

  // Fluxo de "conectar com número de telefone" — usa texto em vez de classe
  // CSS porque essa tela muda de layout com mais frequência que a do QR.
  // Os regex cobrem português e inglês (a sessão roda em pt-BR, mas o
  // WhatsApp às vezes demora a aplicar o locale no primeiro load).
  linkWithPhoneTrigger: /n[uú]mero de telefone|phone number/i,
  phoneNumberInput: 'input[type="text"], input[aria-label*="phone" i], input[aria-label*="telefone" i]',
  nextButton: /avan[cç]ar|next|pr[oó]ximo/i,
  pairingCodeText: '[data-testid="pairing-code"], div.pairing-code, div._pairing-code',
} as const;
