import { Page } from "playwright";
import { IncomingMessage } from "../BrowserDriver";
import { logger } from "../../utils/logger";

/**
 * Registra um MutationObserver dentro da página do WhatsApp Web.
 *
 * IMPORTANTE (motivo da reescrita): o WhatsApp Web só renderiza o conteúdo
 * de uma mensagem na área central da tela quando aquela conversa está
 * ABERTA. Como nossa automação fica parada na tela principal sem nenhuma
 * conversa aberta, observar a área de mensagens (abordagem anterior) nunca
 * detectava nada. A lista de conversas (barra lateral), por outro lado,
 * SEMPRE atualiza — nome do contato + prévia da última mensagem — mesmo
 * sem a conversa estar aberta. É isso que observamos agora.
 *
 * Limitações conhecidas dessa abordagem (heurística, não garantida):
 * - Mídia (foto/áudio/vídeo) aparece na prévia como texto tipo "Foto",
 *   "Áudio" etc, não o conteúdo em si.
 * - Mensagens muito longas vêm truncadas na prévia.
 * - Distinguir "mensagem que EU enviei" de "mensagem recebida" é feito
 *   checando se a prévia começa com "Você:" (prefixo do WhatsApp em pt-BR)
 *   — se o WhatsApp mudar esse texto, essa distinção pode falhar.
 */
export async function attachIncomingMessageListener(
  page: Page,
  sessionId: string,
  onMessage: (msg: IncomingMessage) => void
): Promise<void> {
  const exposedName = `__onWaMessage_${sessionId.replace(/[^a-zA-Z0-9]/g, "")}`;

  await page.exposeFunction(exposedName, (raw: { contact: string; text: string; timestamp: string }) => {
    const message: IncomingMessage = {
      contact: raw.contact,
      type: "text",
      content: raw.text,
      timestamp: raw.timestamp,
    };
    onMessage(message);
  });

  await page.evaluate(
    ({ fnName }) => {
      const seenPreviews = new Map<string, string>();

      function getText(el: Element, selectors: string[]): string | null {
        for (const sel of selectors) {
          const found = el.querySelector(sel);
          if (found?.textContent) return found.textContent.trim();
        }
        return null;
      }

      function extractChatRows(): Element[] {
        return Array.from(
          document.querySelectorAll('[data-testid="cell-frame-container"], div[role="listitem"]')
        );
      }

      function checkChats() {
        const rows = extractChatRows();
        rows.forEach((row, index) => {
          const name = getText(row, ['span[title]', 'span[dir="auto"]']) || `contato-${index}`;
          const preview =
            getText(row, ['span[dir="ltr"]', 'span.selectable-text', '[data-testid="last-msg"]']) || "";
          const key = name;
          const previous = seenPreviews.get(key);

          const isOutgoing = preview.startsWith("Você:") || preview.startsWith("You:");

          if (previous !== undefined && previous !== preview && preview && !isOutgoing) {
            // @ts-expect-error - função exposta dinamicamente pelo Playwright
            window[fnName]?.({
              contact: name,
              text: preview,
              timestamp: new Date().toISOString(),
            });
          }
          seenPreviews.set(key, preview);
        });
      }

      const container = document.querySelector("#pane-side") ?? document.body;
      const observer = new MutationObserver(() => checkChats());
      observer.observe(container, { childList: true, subtree: true, characterData: true });

      // Primeira leitura só registra o estado atual, sem disparar eventos —
      // evita reportar como "novas" mensagens que já estavam na tela.
      checkChats();
    },
    { fnName: exposedName }
  );

  logger.info({ sessionId }, "Listener de mensagens recebidas anexado (observando lista de conversas)");
}
