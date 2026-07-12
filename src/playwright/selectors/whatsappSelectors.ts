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
  // O antigo seletor dependia de aria-label="Search input textbox" (inglês) —
  // como a sessão roda em pt-BR, esse texto vem em português e o seletor
  // nunca batia (causa real dos timeouts de envio). Agora usamos a estrutura
  // do HTML (o único campo editável dentro da barra lateral #side/#pane-side
  // antes de abrir uma conversa é o campo de busca), que não depende de idioma.
  chatSearchInput:
    '#side div[contenteditable="true"], #pane-side div[contenteditable="true"], div[contenteditable="true"][data-tab="3"]',
  messageInput: 'div[contenteditable="true"][data-tab="10"], footer div[contenteditable="true"]',
  sendButton: 'button[aria-label="Send"], button[aria-label="Enviar"], [data-icon="send"]',
  attachButton: 'div[title="Attach"], div[title="Anexar"], button[aria-label="Attach"], button[aria-label="Anexar"], [data-icon="attach"], [data-icon="plus"]',
  attachImageInput: 'input[accept*="image"]',
  attachDocumentInput: 'input[accept*="*"]',
  incomingMessageBubble: 'div[data-testid="msg-container"], div.message-in',
  disconnectedBanner: 'div[data-testid="alert-phone"], div[data-ref]',

  // Fluxo de "conectar com número de telefone" — usa texto em vez de classe
  // CSS porque essa tela muda de layout com mais frequência que a do QR.
  // Os regex cobrem português e inglês (a sessão roda em pt-BR, mas o
  // WhatsApp às vezes demora a aplicar o locale no primeiro load).
  linkWithPhoneTrigger: /n[uú]mero de telefone|phone number/i,
  phoneNumberInput: 'input[type="text"], input[aria-label*="phone" i], input[aria-label*="telefone" i]',
  nextButton: /avan[cç]ar|next|pr[oó]ximo/i,
  pairingCodeText: '[data-testid="pairing-code"], div.pairing-code, div._pairing-code',
} as const;
