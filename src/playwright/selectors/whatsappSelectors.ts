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
  // O antigo seletor dependia de aria-label="Search input textbox" (inglês) —
  // como a sessão roda em pt-BR, esse texto vem em português e o seletor
  // nunca batia (causa real dos timeouts de envio). Agora usamos a estrutura
  // do HTML e incluímos o padrão mais novo do WhatsApp Web (editor "Lexical",
  // atributo data-lexical-editor, que substituiu o antigo sistema data-tab).
  chatSearchInput:
    '#side div[contenteditable="true"][data-lexical-editor="true"], #side div[contenteditable="true"], #pane-side div[contenteditable="true"], div[contenteditable="true"][data-tab="3"]',
  messageInput: 'div[contenteditable="true"][data-tab="10"], footer div[contenteditable="true"]',
  sendButton: 'button[aria-label="Send"], button[aria-label="Enviar"], [data-icon="send"]',
  attachButton: 'div[title="Attach"], div[title="Anexar"], button[aria-label="Attach"], button[aria-label="Anexar"], [data-icon="attach"], [data-icon="plus"]',
  attachImageInput: 'input[accept*="image"]',
  attachDocumentInput: 'input[accept*="*"]',
  incomingMessageBubble: 'div[data-testid="msg-container"], div.message-in',
  disconnectedBanner: 'div[data-testid="alert-phone"], div[data-ref]',

  linkWithPhoneTrigger: /n[uú]mero de telefone|phone number/i,
  phoneNumberInput: 'input[type="text"], input[aria-label*="phone" i], input[aria-label*="telefone" i]',
  nextButton: /avan[cç]ar|next|pr[oó]ximo/i,
  pairingCodeText: '[data-testid="pairing-code"], div.pairing-code, div._pairing-code',
} as const;
