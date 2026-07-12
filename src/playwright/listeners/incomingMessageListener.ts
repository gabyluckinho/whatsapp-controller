import { Page } from "playwright";
import { IncomingMessage } from "../BrowserDriver";
import { WhatsAppSelectors } from "../selectors/whatsappSelectors";
import { logger } from "../../utils/logger";

/**
 * Registra um MutationObserver dentro da página do WhatsApp Web que detecta
 * novas mensagens recebidas e as reporta de volta ao Node via exposeFunction.
 * Preferimos MutationObserver a polling porque: (1) reage instantaneamente,
 * (2) gera bem menos chamadas/CPU que checar o DOM a cada N ms, o que também
 * ajuda a manter o comportamento da aba mais "normal".
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
    ({ selector, fnName }) => {
      const container = document.querySelector(selector) ?? document.body;

      const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          mutation.addedNodes.forEach((node) => {
            if (!(node instanceof HTMLElement)) return;
            if (!node.matches?.(".message-in, [data-testid='msg-container']")) return;

            const textEl = node.querySelector("span.selectable-text, span[dir='ltr']");
            const contact = document.title || "desconhecido";

            // @ts-expect-error - função exposta dinamicamente pelo Playwright
            window[fnName]?.({
              contact,
              text: textEl?.textContent ?? "[mídia ou tipo não textual]",
              timestamp: new Date().toISOString(),
            });
          });
        }
      });

      observer.observe(container, { childList: true, subtree: true });
    },
    { selector: WhatsAppSelectors.incomingMessageBubble, fnName: exposedName }
  );

  logger.info({ sessionId }, "Listener de mensagens recebidas anexado");
}

