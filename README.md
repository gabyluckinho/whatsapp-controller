# WhatsApp Browser Controller

Controlador de múltiplas sessões de WhatsApp Web via Playwright/Chromium, com API interna para consumo pelo n8n. MVP com 3 sessões, arquitetura pronta para escalar para dezenas apenas via configuração.

## ⚠️ Leia antes de rodar em produção

Este projeto automatiza o WhatsApp Web por navegador — **isso viola os Termos de Serviço do WhatsApp** e há risco real de banimento de número. O projeto inclui camadas de mitigação (não de "burla" de segurança):

- **Delays humanizados** em toda ação de digitação/clique (`src/utils/humanBehavior.ts`).
- **Rate limit orgânico por sessão**, com período de "aquecimento" para números novos (`WARMUP_PERIOD_HOURS`, `WARMUP_MAX_MESSAGES_PER_MINUTE` no `.env`).
- **Fingerprint estável por sessão** (viewport/user-agent consistentes, não trocam a cada restart) (`src/playwright/antiDetection.ts`).
- **Remoção de sinais óbvios de automação** (`navigator.webdriver`, `window.chrome` ausente).
- **Isolamento total de falhas**: cada sessão tem seu próprio browser context, fila e worker — a queda de uma nunca derruba as outras.
- **Stagger de inicialização**: sessões não sobem todas no mesmo milissegundo.

Mesmo com essas medidas, **não existe garantia contra banimento**. Recomenda-se: números com histórico de uso real antes de automatizar, volume conservador, e um plano de contingência (números reserva) no lado do negócio.

## Requisitos

- Docker + Docker Compose (ou Portainer)
- Uma instância n8n acessível via HTTPS
- Um projeto Supabase (Postgres) já criado
- 3 números de WhatsApp dedicados à automação

## Configuração

1. Copie `.env.example` para `.env` e preencha todas as variáveis, incluindo `PLATFORM_ADMIN_PASSWORD` (senha de acesso ao painel — separada da `API_KEY`, que é para o n8n).
2. Rode a migration em `src/database/migrations/001_init.sql` no SQL Editor do Supabase.
3. A variável `SESSIONS` no `.env` agora é **só uma semente opcional** para o primeiro boot (se a tabela `sessions` estiver vazia). Depois do primeiro deploy, números são adicionados/removidos pela **Plataforma** (painel web), não editando `.env` nem redeployando.

## A Plataforma (painel administrativo)

Acesse `http://SEU_DOMINIO_OU_IP:3000/platform` (ou a URL configurada no Traefik). Login com `PLATFORM_ADMIN_PASSWORD`.

No painel você pode, em tempo real e sem tocar em código ou infraestrutura:

- **Adicionar um número novo**: cria a sessão, sobe o navegador isolado e o worker de fila automaticamente; o QR code aparece no card da sessão em poucos segundos.
- **Ver o status de cada sessão** (aguardando QR, conectado, desconectado, etc.), atualizado a cada 5s.
- **Reiniciar, pausar/retomar, ver logs recentes e remover** qualquer sessão individualmente.

Por baixo dos panos, o painel usa a mesma API interna que o n8n usa (`/sessions/...`) — a senha do painel só existe para dar a um humano acesso à `API_KEY` de forma mais amigável que copiar/colar a chave manualmente. O n8n continua recebendo os webhooks de eventos (`message.received`, `message.sent`, `session.status_changed`) normalmente; a Plataforma não substitui o n8n, só assume a parte de **provisionamento e operação dos números**, que antes exigia mexer no `.env`/redeploy.

## Rodando localmente (dev)

```bash
npm install
npx playwright install --with-deps chromium
cp .env.example .env   # e preencha
npm run dev
```

Acesse `http://localhost:3000/platform`, faça login, e use o botão "Adicionar número" para criar a primeira sessão — não é mais necessário pré-configurar `SESSIONS` no `.env` (embora ainda funcione como semente do primeiro boot, se preferir).

## Rodando com Docker Compose

```bash
docker compose up -d --build
```

O painel fica em `http://SEU_IP:3000/platform` (mesmo container da API — não há mais um serviço de dashboard separado).

## Deploy via Portainer

1. Build da imagem do Controller e publique em um registry acessível pela VPS (ou configure build a partir do repositório Git direto no Portainer).
2. Em Portainer → Stacks → Add stack, aponte para `portainer/stack.yml`.
3. Preencha as variáveis de ambiente da stack (API_KEY, PLATFORM_ADMIN_PASSWORD, SUPABASE_URL, etc.).
4. Confirme que a rede `wa-net` referenciada já existe (ou ajuste para criar uma nova).

Note que a stack usa **um único volume** (`sessions_data`) montado em `/data/sessions` — isso é proposital: sessões criadas dinamicamente pela Plataforma (além das iniciais) já persistem automaticamente, sem precisar editar a stack a cada número novo.

## Autenticação da API

Toda rota (exceto `/health`) exige o header:

```
x-api-key: SEU_API_KEY_DO_.ENV
```

## Endpoints principais

| Rota | Método | Descrição |
|---|---|---|
| `/sessions` | GET | Lista sessões e status |
| `/sessions` | POST | Cria uma sessão nova `{ "id": "04", "name": "Financeiro" }` (é o que a Plataforma usa) |
| `/sessions/:id` | DELETE | Remove/desativa uma sessão |
| `/sessions/:id/status` | GET | Status de uma sessão |
| `/sessions/:id/qrcode` | GET | QR code atual |
| `/sessions/:id/restart` | POST | Reinicia a sessão |
| `/sessions/:id/pause` / `/resume` | POST | Pausa/retoma consumo da fila |
| `/sessions/:id/messages/text` | POST | `{ "contact": "...", "text": "..." }` |
| `/sessions/:id/messages/image` \| `audio` \| `document` \| `video` | POST | `{ "contact": "...", "filePath": "...", "caption"?: "..." }` |
| `/sessions/:id/queue/clear` | POST | Limpa a fila da sessão |
| `/sessions/:id/logs` | GET | Últimos logs |
| `/health` | GET | Health check (sem auth) |

Todo envio retorna `202 Accepted` com um `jobId` — o resultado real (sucesso/erro) chega via webhook para o n8n (`message.sent`), não na resposta HTTP.

## Testes

```bash
npm test
```

## O que ainda falta implementar (próximas etapas)

Este esqueleto cobre: sessões dinâmicas com isolamento de falha, fila com workers rodando de fato (antes só existiam, não eram instanciados — corrigido), listener de mensagens recebidas conectado, e a Plataforma (painel web) para adicionar/remover números e operar sessões sem tocar em código. Falta:

- **Métricas de CPU/memória por sessão** persistidas em `queue_metrics` e exibidas no painel (hoje o painel mostra status/logs, não uso de recursos).
- **Validação contra o WhatsApp Web real**: os seletores em `src/playwright/selectors/whatsappSelectors.ts` foram escritos com base em atributos estáveis (aria-label, data-testid), mas o WhatsApp muda o DOM com frequência — o primeiro teste com QR code real provavelmente vai exigir ajuste fino de 1-2 seletores.
- **HTTPS/domínio para a Plataforma em produção**: o painel funciona em HTTP puro localmente; em produção, sirva-o atrás do Traefik (já configurado no `docker-compose.yml`/`portainer/stack.yml`) para ter TLS.

Posso seguir implementando qualquer um desses pontos agora — me diga por qual prefere continuar.

