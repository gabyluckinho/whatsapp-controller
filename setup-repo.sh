#!/usr/bin/env bash
set -e
echo "Criando estrutura do projeto..."

mkdir -p "."
cat > ".env.example" << '___CLAUDE_EOF_MARKER___'
# ---- API ----
PORT=3000
API_KEY=troque-por-uma-chave-forte-aqui
NODE_ENV=production

# ---- Redis ----
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=

# ---- Supabase ----
SUPABASE_URL=https://SEU-PROJETO.supabase.co
SUPABASE_SERVICE_ROLE_KEY=troque-por-sua-service-role-key

# ---- n8n Webhook ----
N8N_WEBHOOK_URL=https://seu-n8n.dominio.com/webhook/whatsapp-events
N8N_WEBHOOK_SECRET=troque-por-um-segredo-compartilhado

# ---- Sessões ----
# OPCIONAL: usado só para semear a primeira execução (tabela `sessions` vazia).
# Depois do primeiro boot, adicione/remova números pela Plataforma (dashboard),
# não editando esta variável. Formato: id,nome separados por ;
SESSIONS=01,Sessao-01;02,Sessao-02;03,Sessao-03

# ---- Plataforma (dashboard administrativo) ----
# Senha usada para logar no painel web (separada da API_KEY, que é para o n8n/API).
PLATFORM_ADMIN_PASSWORD=troque-por-uma-senha-forte

# ---- Anti-detecção / comportamento humano ----
# Delay mínimo/máximo (ms) entre ações dentro da mesma sessão
HUMAN_DELAY_MIN_MS=1800
HUMAN_DELAY_MAX_MS=6500
# Máximo de mensagens por minuto, por sessão (limite orgânico, não só técnico)
MAX_MESSAGES_PER_MINUTE=8
# Período de "aquecimento" de uma sessão nova (horas) com volume reduzido
WARMUP_PERIOD_HOURS=48
WARMUP_MAX_MESSAGES_PER_MINUTE=2

___CLAUDE_EOF_MARKER___

mkdir -p "."
cat > "README.md" << '___CLAUDE_EOF_MARKER___'
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

___CLAUDE_EOF_MARKER___

mkdir -p "."
cat > "docker-compose.simples.yml" << '___CLAUDE_EOF_MARKER___'
# ---------------------------------------------------------------------------
# VERSÃO SIMPLIFICADA PARA O PRIMEIRO DEPLOY
# ---------------------------------------------------------------------------
# Sem Traefik/domínio — publica a porta 3000 direto na VPS. Acesse depois por:
#   Plataforma (painel): http://SEU_IP:3000/platform
#   API interna (n8n):   http://SEU_IP:3000
#
# Quando quiser HTTPS + domínio bonito, use o docker-compose.yml normal
# (com labels do Traefik) no lugar deste.
# ---------------------------------------------------------------------------
version: "3.9"

services:
  controller:
    build:
      context: .
      dockerfile: docker/controller/Dockerfile
    container_name: wa-controller
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "3000:3000"
    volumes:
      - sessions_data:/data/sessions
    depends_on:
      - redis
    networks:
      - wa-net
    deploy:
      resources:
        limits:
          memory: 3g
        reservations:
          memory: 1g

  redis:
    image: redis:7-alpine
    container_name: wa-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis_data:/data
    networks:
      - wa-net

networks:
  wa-net:
    external: false

volumes:
  sessions_data:
  redis_data:

___CLAUDE_EOF_MARKER___

mkdir -p "."
cat > "docker-compose.yml" << '___CLAUDE_EOF_MARKER___'
version: "3.9"

services:
  controller:
    build:
      context: .
      dockerfile: docker/controller/Dockerfile
    container_name: wa-controller
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - sessions_data:/data/sessions
    depends_on:
      - redis
    networks:
      - wa-net
    labels:
      - "traefik.enable=true"
      # API interna (consumida pelo n8n)
      - "traefik.http.routers.wa-controller.rule=Host(`api-whatsapp.SEU_DOMINIO.com`)"
      - "traefik.http.routers.wa-controller.entrypoints=websecure"
      - "traefik.http.routers.wa-controller.tls.certresolver=letsencrypt"
      - "traefik.http.services.wa-controller.loadbalancer.server.port=3000"
      # Plataforma (dashboard) — mesmo container, mesmo processo, rota /platform.
      # Se preferir um subdomínio dedicado para o painel, duplique o router
      # abaixo apontando para o mesmo serviço, só trocando o Host() e
      # adicionando um PathPrefix ou redirecionamento para /platform.
      - "traefik.http.routers.wa-platform.rule=Host(`painel-whatsapp.SEU_DOMINIO.com`)"
      - "traefik.http.routers.wa-platform.entrypoints=websecure"
      - "traefik.http.routers.wa-platform.tls.certresolver=letsencrypt"
      - "traefik.http.services.wa-platform.loadbalancer.server.port=3000"
    # Limites de recurso: cada Chromium consome de forma variável, mas
    # 3 sessões concorrentes cabem confortavelmente numa VPS de 4-8GB.
    deploy:
      resources:
        limits:
          memory: 3g
        reservations:
          memory: 1g

  redis:
    image: redis:7-alpine
    container_name: wa-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis_data:/data
    networks:
      - wa-net

networks:
  wa-net:
    external: false

volumes:
  sessions_data:
  redis_data:

___CLAUDE_EOF_MARKER___

mkdir -p "docker/controller"
cat > "docker/controller/Dockerfile" << '___CLAUDE_EOF_MARKER___'
# Imagem oficial do Playwright já vem com Chromium + todas as libs do SO
# necessárias (evita o clássico problema de dependências de fonte/GTK faltando).
FROM mcr.microsoft.com/playwright:v1.47.0-jammy AS base

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev=false

COPY tsconfig.json ./
COPY src ./src

RUN npm run build

# ---- Imagem final, mais enxuta ----
FROM mcr.microsoft.com/playwright:v1.47.0-jammy AS runtime

WORKDIR /app
ENV NODE_ENV=production

COPY --from=base /app/package.json ./package.json
COPY --from=base /app/node_modules ./node_modules
COPY --from=base /app/dist ./dist
COPY public ./public

# Diretório onde os volumes por sessão serão montados (perfis do Chromium)
RUN mkdir -p /data/sessions

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>{if(r.status!==200)process.exit(1)}).catch(()=>process.exit(1))"

EXPOSE 3000

CMD ["node", "dist/index.js"]

___CLAUDE_EOF_MARKER___

mkdir -p "."
cat > "package.json" << '___CLAUDE_EOF_MARKER___'
{
  "name": "whatsapp-browser-controller",
  "version": "0.1.0",
  "description": "Controlador de múltiplas sessões de WhatsApp Web via Playwright, com API interna para integração com n8n.",
  "main": "dist/index.js",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/index.js",
    "lint": "eslint src --ext .ts",
    "test": "vitest run"
  },
  "dependencies": {
    "playwright": "^1.47.0",
    "express": "^4.19.2",
    "bullmq": "^5.12.0",
    "ioredis": "^5.4.1",
    "@supabase/supabase-js": "^2.45.4",
    "pino": "^9.4.0",
    "pino-pretty": "^11.2.2",
    "dotenv": "^16.4.5",
    "zod": "^3.23.8",
    "express-rate-limit": "^7.4.0",
    "qrcode": "^1.5.4",
    "uuid": "^10.0.0",
    "node-cron": "^3.0.3"
  },
  "devDependencies": {
    "typescript": "^5.5.4",
    "tsx": "^4.19.0",
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.15",
    "@types/qrcode": "^1.5.5",
    "@types/uuid": "^10.0.0",
    "vitest": "^2.0.5",
    "eslint": "^8.57.0"
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "portainer"
cat > "portainer/stack.yml" << '___CLAUDE_EOF_MARKER___'
# Stack pronta para deploy via Portainer > Stacks > Add Stack > Repository/Upload.
# As variáveis de ambiente (API_KEY, SUPABASE_URL, etc.) devem ser configuradas
# na seção "Environment variables" do próprio Portainer ao criar a stack,
# ou via um arquivo .env referenciado no repositório.
#
# O Controller expõe TANTO a API interna (para o n8n) QUANTO a Plataforma
# (dashboard, em /platform) na mesma porta 3000 — um único container.
version: "3.9"

services:
  controller:
    image: SEU_REGISTRY/wa-controller:latest
    restart: unless-stopped
    environment:
      - PORT=3000
      - API_KEY=${API_KEY}
      - PLATFORM_ADMIN_PASSWORD=${PLATFORM_ADMIN_PASSWORD}
      - NODE_ENV=production
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
      - N8N_WEBHOOK_URL=${N8N_WEBHOOK_URL}
      - N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}
      - SESSIONS=${SESSIONS}
      - HUMAN_DELAY_MIN_MS=1800
      - HUMAN_DELAY_MAX_MS=6500
      - MAX_MESSAGES_PER_MINUTE=8
      - WARMUP_PERIOD_HOURS=48
      - WARMUP_MAX_MESSAGES_PER_MINUTE=2
    volumes:
      - sessions_data:/data/sessions
      # Um único volume pai: sessões adicionadas dinamicamente pela Plataforma
      # (além das iniciais) já persistem automaticamente, sem precisar editar
      # esta stack ou redeployar a cada número novo.
    networks:
      - wa-net
    deploy:
      replicas: 1
      resources:
        limits:
          memory: 3G
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.wa-controller.rule=Host(`api-whatsapp.SEU_DOMINIO.com`)"
        - "traefik.http.routers.wa-controller.entrypoints=websecure"
        - "traefik.http.routers.wa-controller.tls.certresolver=letsencrypt"
        - "traefik.http.services.wa-controller.loadbalancer.server.port=3000"
        - "traefik.http.routers.wa-platform.rule=Host(`painel-whatsapp.SEU_DOMINIO.com`)"
        - "traefik.http.routers.wa-platform.entrypoints=websecure"
        - "traefik.http.routers.wa-platform.tls.certresolver=letsencrypt"
        - "traefik.http.services.wa-platform.loadbalancer.server.port=3000"

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis_data:/data
    networks:
      - wa-net

networks:
  wa-net:
    external: true # aponta para a rede compartilhada do Traefik/n8n já existente na VPS

volumes:
  sessions_data:
  redis_data:

___CLAUDE_EOF_MARKER___

mkdir -p "public/platform"
cat > "public/platform/index.html" << '___CLAUDE_EOF_MARKER___'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Plataforma WhatsApp — Painel</title>
<style>
  :root {
    --bg: #0f1115;
    --panel: #171a21;
    --panel-2: #1f232c;
    --border: #2a2f3a;
    --text: #e6e8ec;
    --muted: #8b93a3;
    --accent: #25d366;
    --accent-dark: #1da851;
    --danger: #e5484d;
    --warn: #e0a72a;
    --blue: #4f8ff7;
    --radius: 10px;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
  }
  .hidden { display: none !important; }

  /* ---- Login ---- */
  #login-screen {
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .login-box {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 32px;
    width: 320px;
  }
  .login-box h1 {
    font-size: 18px;
    margin: 0 0 4px;
  }
  .login-box p {
    color: var(--muted);
    font-size: 13px;
    margin: 0 0 20px;
  }
  input[type="password"], input[type="text"] {
    width: 100%;
    padding: 10px 12px;
    border-radius: 8px;
    border: 1px solid var(--border);
    background: var(--panel-2);
    color: var(--text);
    font-size: 14px;
    margin-bottom: 12px;
  }
  button {
    cursor: pointer;
    border: none;
    border-radius: 8px;
    padding: 10px 16px;
    font-size: 14px;
    font-weight: 600;
    transition: opacity 0.15s;
  }
  button:hover { opacity: 0.88; }
  button.primary { background: var(--accent); color: #05130a; width: 100%; }
  button.secondary { background: var(--panel-2); color: var(--text); border: 1px solid var(--border); }
  button.danger { background: rgba(229,72,77,0.15); color: var(--danger); border: 1px solid rgba(229,72,77,0.3); }
  #login-error { color: var(--danger); font-size: 13px; margin-top: 8px; min-height: 16px; }

  /* ---- App shell ---- */
  #app-screen { min-height: 100vh; }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 18px 28px;
    border-bottom: 1px solid var(--border);
  }
  header h1 { font-size: 16px; margin: 0; display: flex; align-items: center; gap: 8px; }
  header h1 .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--accent); }
  main { padding: 24px 28px; max-width: 1100px; margin: 0 auto; }

  .toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
  .toolbar h2 { font-size: 14px; color: var(--muted); font-weight: 500; margin: 0; }

  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 16px; }

  .card {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 18px;
  }
  .card-head { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 10px; }
  .card-head .name { font-weight: 600; font-size: 15px; }
  .card-head .id { color: var(--muted); font-size: 12px; }

  .badge {
    font-size: 11px;
    font-weight: 600;
    padding: 3px 9px;
    border-radius: 999px;
    text-transform: uppercase;
    letter-spacing: 0.02em;
  }
  .badge.CONECTADO { background: rgba(37,211,102,0.15); color: var(--accent); }
  .badge.AGUARDANDO_QR { background: rgba(224,167,42,0.15); color: var(--warn); }
  .badge.CONECTANDO { background: rgba(79,143,247,0.15); color: var(--blue); }
  .badge.DESCONECTADO, .badge.ERRO { background: rgba(229,72,77,0.15); color: var(--danger); }
  .badge.REINICIANDO { background: rgba(224,167,42,0.15); color: var(--warn); }
  .badge.PAUSADO { background: rgba(139,147,163,0.15); color: var(--muted); }

  .qr-box {
    display: flex;
    align-items: center;
    justify-content: center;
    background: #fff;
    border-radius: 8px;
    padding: 10px;
    margin: 12px 0;
  }
  .qr-box img { width: 100%; max-width: 220px; display: block; }
  .qr-placeholder {
    color: var(--muted);
    font-size: 12px;
    text-align: center;
    padding: 24px 0;
  }

  .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
  .actions button { flex: 1 1 auto; font-size: 12px; padding: 8px 10px; }

  .add-card {
    border: 1px dashed var(--border);
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 180px;
    color: var(--muted);
    cursor: pointer;
    font-size: 14px;
  }
  .add-card:hover { border-color: var(--accent); color: var(--accent); }

  /* ---- Modal ---- */
  .modal-overlay {
    position: fixed; inset: 0; background: rgba(0,0,0,0.6);
    display: flex; align-items: center; justify-content: center; z-index: 10;
  }
  .modal {
    background: var(--panel); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 24px; width: 340px;
  }
  .modal h3 { margin: 0 0 4px; font-size: 15px; }
  .modal p { color: var(--muted); font-size: 12px; margin: 0 0 16px; }
  .modal-actions { display: flex; gap: 8px; margin-top: 4px; }
  .modal-actions button { flex: 1; }

  .logs-panel {
    max-height: 240px; overflow-y: auto; background: var(--panel-2);
    border-radius: 8px; padding: 10px; font-size: 11px; font-family: monospace;
    margin-top: 10px; color: var(--muted);
  }
  .logs-panel div { padding: 2px 0; border-bottom: 1px solid var(--border); }

  .toast {
    position: fixed; bottom: 20px; right: 20px; background: var(--panel-2);
    border: 1px solid var(--border); padding: 12px 16px; border-radius: 8px;
    font-size: 13px; z-index: 20;
  }
  .toast.error { border-color: rgba(229,72,77,0.5); color: var(--danger); }
</style>
</head>
<body>

<div id="login-screen">
  <div class="login-box">
    <h1>Plataforma WhatsApp</h1>
    <p>Painel administrativo das sessões conectadas</p>
    <input type="password" id="password-input" placeholder="Senha do painel" />
    <button class="primary" onclick="login()">Entrar</button>
    <div id="login-error"></div>
  </div>
</div>

<div id="app-screen" class="hidden">
  <header>
    <h1><span class="dot"></span> Plataforma WhatsApp</h1>
    <button class="secondary" onclick="logout()">Sair</button>
  </header>
  <main>
    <div class="toolbar">
      <h2 id="session-count">Carregando sessões…</h2>
      <button class="primary" onclick="openAddModal()">+ Adicionar número</button>
    </div>
    <div class="grid" id="sessions-grid"></div>
  </main>
</div>

<div id="add-modal" class="modal-overlay hidden">
  <div class="modal">
    <h3>Adicionar novo número</h3>
    <p>Cria a sessão e já disponibiliza o QR code para escanear.</p>
    <input type="text" id="new-session-id" placeholder="Identificador (ex: 04)" />
    <input type="text" id="new-session-name" placeholder="Nome (ex: Financeiro)" />
    <div class="modal-actions">
      <button class="secondary" onclick="closeAddModal()">Cancelar</button>
      <button class="primary" onclick="createSession()">Criar</button>
    </div>
  </div>
</div>

<script>
const state = { apiKey: localStorage.getItem('wa_platform_api_key') || null, pollTimer: null, logsOpenFor: null };

function showToast(message, isError) {
  const el = document.createElement('div');
  el.className = 'toast' + (isError ? ' error' : '');
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3500);
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    headers: { 'Content-Type': 'application/json', 'x-api-key': state.apiKey, ...(options.headers || {}) },
  });
  if (res.status === 401) { logout(); throw new Error('Sessão expirada, faça login novamente'); }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error ? JSON.stringify(data.error) : 'Erro na requisição');
  return data;
}

async function login() {
  const password = document.getElementById('password-input').value;
  const errorEl = document.getElementById('login-error');
  errorEl.textContent = '';
  try {
    const res = await fetch('/platform/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password }),
    });
    const data = await res.json();
    if (!res.ok) { errorEl.textContent = data.error || 'Falha no login'; return; }
    state.apiKey = data.apiKey;
    localStorage.setItem('wa_platform_api_key', state.apiKey);
    enterApp();
  } catch (e) {
    errorEl.textContent = 'Não foi possível conectar ao servidor';
  }
}

function logout() {
  localStorage.removeItem('wa_platform_api_key');
  state.apiKey = null;
  if (state.pollTimer) clearInterval(state.pollTimer);
  document.getElementById('app-screen').classList.add('hidden');
  document.getElementById('login-screen').classList.remove('hidden');
}

function enterApp() {
  document.getElementById('login-screen').classList.add('hidden');
  document.getElementById('app-screen').classList.remove('hidden');
  loadSessions();
  state.pollTimer = setInterval(loadSessions, 5000);
}

function openAddModal() { document.getElementById('add-modal').classList.remove('hidden'); }
function closeAddModal() {
  document.getElementById('add-modal').classList.add('hidden');
  document.getElementById('new-session-id').value = '';
  document.getElementById('new-session-name').value = '';
}

async function createSession() {
  const id = document.getElementById('new-session-id').value.trim();
  const name = document.getElementById('new-session-name').value.trim();
  if (!id || !name) { showToast('Preencha identificador e nome', true); return; }
  try {
    await api('/sessions', { method: 'POST', body: JSON.stringify({ id, name }) });
    showToast('Sessão criada! Aguarde o QR code aparecer.');
    closeAddModal();
    loadSessions();
  } catch (e) {
    showToast(e.message, true);
  }
}

async function removeSession(id) {
  if (!confirm('Remover a sessão "' + id + '"? Isso desconecta o navegador e desativa o número na plataforma.')) return;
  try {
    await api('/sessions/' + id, { method: 'DELETE' });
    showToast('Sessão removida');
    loadSessions();
  } catch (e) {
    showToast(e.message, true);
  }
}

async function restartSession(id) {
  try { await api('/sessions/' + id + '/restart', { method: 'POST' }); showToast('Reinício solicitado'); loadSessions(); }
  catch (e) { showToast(e.message, true); }
}
async function pauseSession(id) {
  try { await api('/sessions/' + id + '/pause', { method: 'POST' }); loadSessions(); }
  catch (e) { showToast(e.message, true); }
}
async function resumeSession(id) {
  try { await api('/sessions/' + id + '/resume', { method: 'POST' }); loadSessions(); }
  catch (e) { showToast(e.message, true); }
}

async function toggleLogs(id) {
  state.logsOpenFor = state.logsOpenFor === id ? null : id;
  loadSessions();
}

async function loadSessions() {
  try {
    const data = await api('/sessions');
    renderSessions(data.sessions || []);
  } catch (e) {
    showToast(e.message, true);
  }
}

async function renderSessions(sessions) {
  const grid = document.getElementById('sessions-grid');
  document.getElementById('session-count').textContent =
    sessions.length + (sessions.length === 1 ? ' sessão conectada' : ' sessões conectadas');

  const cards = await Promise.all(sessions.map(renderCard));
  grid.innerHTML = cards.join('') + `
    <div class="add-card" onclick="openAddModal()">+ Adicionar número</div>
  `;
}

async function renderCard(session) {
  let qrHtml = '';
  if (session.status === 'AGUARDANDO_QR' || session.status === 'CONECTANDO') {
    try {
      const qrData = await api('/sessions/' + session.id + '/qrcode');
      qrHtml = qrData.qrCode
        ? `<div class="qr-box"><img src="${qrData.qrCode}" alt="QR code" /></div>`
        : `<div class="qr-box"><div class="qr-placeholder">Gerando QR code…</div></div>`;
    } catch (e) {
      qrHtml = `<div class="qr-box"><div class="qr-placeholder">QR indisponível</div></div>`;
    }
  }

  let logsHtml = '';
  if (state.logsOpenFor === session.id) {
    try {
      const logData = await api('/sessions/' + session.id + '/logs');
      const items = (logData.logs || []).slice(0, 30)
        .map(l => `<div>[${l.level}] ${l.event}: ${l.message || ''}</div>`).join('');
      logsHtml = `<div class="logs-panel">${items || 'Sem logs recentes'}</div>`;
    } catch (e) {
      logsHtml = `<div class="logs-panel">Falha ao carregar logs</div>`;
    }
  }

  const isPaused = session.status === 'PAUSADO';

  return `
    <div class="card">
      <div class="card-head">
        <div>
          <div class="name">${session.name}</div>
          <div class="id">#${session.id}</div>
        </div>
        <span class="badge ${session.status}">${session.status.replace('_', ' ')}</span>
      </div>
      ${qrHtml}
      <div class="actions">
        <button class="secondary" onclick="restartSession('${session.id}')">Reiniciar</button>
        ${isPaused
          ? `<button class="secondary" onclick="resumeSession('${session.id}')">Retomar</button>`
          : `<button class="secondary" onclick="pauseSession('${session.id}')">Pausar</button>`}
        <button class="secondary" onclick="toggleLogs('${session.id}')">Logs</button>
        <button class="danger" onclick="removeSession('${session.id}')">Remover</button>
      </div>
      ${logsHtml}
    </div>
  `;
}

// Auto-login se já houver API key salva
if (state.apiKey) { enterApp(); }

document.getElementById('password-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') login();
});
</script>
</body>
</html>

___CLAUDE_EOF_MARKER___

mkdir -p "src/api/middlewares"
cat > "src/api/middlewares/auth.ts" << '___CLAUDE_EOF_MARKER___'
import { Request, Response, NextFunction } from "express";
import { env } from "../../config/env";

export function apiKeyAuth(req: Request, res: Response, next: NextFunction): void {
  const key = req.header("x-api-key");
  if (!key || key !== env.API_KEY) {
    res.status(401).json({ error: "API key ausente ou inválida" });
    return;
  }
  next();
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/api/middlewares"
cat > "src/api/middlewares/errorHandler.ts" << '___CLAUDE_EOF_MARKER___'
import { Request, Response, NextFunction } from "express";
import { logger } from "../../utils/logger";

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction): void {
  logger.error({ err, path: req.path }, "Erro não tratado na API");
  const message = err instanceof Error ? err.message : "Erro interno";
  res.status(500).json({ error: message });
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/api/middlewares"
cat > "src/api/middlewares/rateLimiter.ts" << '___CLAUDE_EOF_MARKER___'
import rateLimit from "express-rate-limit";

/**
 * Rate limit na CAMADA DE API (proteção do próprio servidor contra abuso do
 * n8n/cliente). Não confundir com o rate limit orgânico da fila (QueueWorker),
 * que existe para proteger o NÚMERO de WhatsApp contra banimento — são
 * limites com propósitos diferentes e ambos são necessários.
 */
export const apiRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Muitas requisições. Tente novamente em instantes." },
});

/** Limite bem mais rígido para o login da Plataforma — protege contra força bruta na senha. */
export const platformLoginRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Muitas tentativas de login. Aguarde alguns minutos." },
});

___CLAUDE_EOF_MARKER___

mkdir -p "src/api/routes"
cat > "src/api/routes/health.routes.ts" << '___CLAUDE_EOF_MARKER___'
import { Router } from "express";
import { SessionManager } from "../../sessions/SessionManager";

export function healthRouter(sessionManager: SessionManager): Router {
  const router = Router();

  router.get("/", (_req, res) => {
    const sessions = sessionManager.list().map((s) => ({ id: s.sessionId, status: s.getState() }));
    res.json({ status: "ok", uptime: process.uptime(), sessions });
  });

  return router;
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/api/routes"
cat > "src/api/routes/messages.routes.ts" << '___CLAUDE_EOF_MARKER___'
import { Router } from "express";
import { z } from "zod";
import { SessionManager } from "../../sessions/SessionManager";

const textSchema = z.object({ contact: z.string().min(3), text: z.string().min(1) });
const mediaSchema = z.object({ contact: z.string().min(3), filePath: z.string().min(1), caption: z.string().optional() });

export function messagesRouter(sessionManager: SessionManager): Router {
  const router = Router();
  const queueManager = sessionManager.getQueueManager();

  async function enqueue(
    req: any,
    res: any,
    type: "text" | "image" | "audio" | "document" | "video",
    schema: z.ZodTypeAny
  ) {
    const supervisor = sessionManager.requireSession(req.params.id);
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }

    const { contact, ...rest } = parsed.data;
    const jobId = await queueManager.enqueue(supervisor.sessionId, supervisor.getCreatedAt(), {
      sessionId: supervisor.sessionId,
      contact,
      type,
      payload: rest,
    });

    res.status(202).json({ jobId, queued: true });
  }

  router.post("/:id/messages/text", (req, res) => enqueue(req, res, "text", textSchema));
  router.post("/:id/messages/image", (req, res) => enqueue(req, res, "image", mediaSchema));
  router.post("/:id/messages/audio", (req, res) => enqueue(req, res, "audio", mediaSchema));
  router.post("/:id/messages/document", (req, res) => enqueue(req, res, "document", mediaSchema));
  router.post("/:id/messages/video", (req, res) => enqueue(req, res, "video", mediaSchema));

  router.post("/:id/queue/clear", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await queueManager.clear(supervisor.sessionId);
    res.json({ message: "Fila limpa" });
  });

  return router;
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/api/routes"
cat > "src/api/routes/platform.routes.ts" << '___CLAUDE_EOF_MARKER___'
import { Router } from "express";
import { z } from "zod";
import { env } from "../../config/env";
import { logger } from "../../utils/logger";

const loginSchema = z.object({ password: z.string().min(1) });

/**
 * Login simples da Plataforma (dashboard administrativo). É intencionalmente
 * separado da API_KEY usada pelo n8n: a senha do painel (PLATFORM_ADMIN_PASSWORD)
 * é o que um humano digita; depois de validada, devolvemos a própria API_KEY
 * para o navegador guardar (localStorage) e usar nas chamadas seguintes às
 * mesmas rotas /sessions que o n8n usa — um único mecanismo de autorização
 * de API, duas portas de entrada (humano via senha, n8n via API key direta).
 */
export function platformAuthRouter(): Router {
  const router = Router();

  router.post("/login", (req, res) => {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "Senha ausente" });
      return;
    }

    if (parsed.data.password !== env.PLATFORM_ADMIN_PASSWORD) {
      logger.warn({ ip: req.ip }, "Tentativa de login na Plataforma com senha incorreta");
      res.status(401).json({ error: "Senha incorreta" });
      return;
    }

    res.json({ apiKey: env.API_KEY });
  });

  return router;
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/api/routes"
cat > "src/api/routes/sessions.routes.ts" << '___CLAUDE_EOF_MARKER___'
import { Router } from "express";
import { z } from "zod";
import { SessionManager } from "../../sessions/SessionManager";
import { LogRepository } from "../../database/repositories/LogRepository";

const createSessionSchema = z.object({
  id: z
    .string()
    .min(1)
    .max(20)
    .regex(/^[a-zA-Z0-9_-]+$/, "id deve conter apenas letras, números, hífen ou underscore"),
  name: z.string().min(1).max(80),
});

export function sessionsRouter(sessionManager: SessionManager, logRepository: LogRepository): Router {
  const router = Router();

  router.get("/", (_req, res) => {
    const sessions = sessionManager.list().map((s) => ({
      id: s.sessionId,
      name: s.sessionName,
      status: s.getState(),
      createdAt: s.getCreatedAt(),
    }));
    res.json({ sessions });
  });

  // Usado pela Plataforma para adicionar um número novo em tempo real,
  // sem redeploy: cria o registro no Supabase, sobe o supervisor e o
  // worker da fila, e o QR code fica disponível em segundos.
  router.post("/", async (req, res) => {
    const parsed = createSessionSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    try {
      const supervisor = await sessionManager.addSession(parsed.data.id, parsed.data.name);
      res.status(201).json({ id: supervisor.sessionId, name: supervisor.sessionName, status: supervisor.getState() });
    } catch (error) {
      res.status(409).json({ error: error instanceof Error ? error.message : "Falha ao criar sessão" });
    }
  });

  router.delete("/:id", async (req, res) => {
    try {
      await sessionManager.removeSession(req.params.id);
      res.status(200).json({ message: "Sessão removida" });
    } catch (error) {
      res.status(404).json({ error: error instanceof Error ? error.message : "Sessão não encontrada" });
    }
  });

  router.get("/:id/status", (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    res.json({ id: supervisor.sessionId, status: supervisor.getState() });
  });

  router.get("/:id/qrcode", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    const qr = await sessionManager.getQrCode(supervisor.sessionId);
    res.json({ id: supervisor.sessionId, status: supervisor.getState(), qrCode: qr });
  });

  router.post("/:id/restart", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await supervisor.restart();
    res.status(202).json({ message: "Reinício solicitado" });
  });

  router.post("/:id/pause", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await supervisor.pause();
    res.status(200).json({ message: "Sessão pausada" });
  });

  router.post("/:id/resume", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    await supervisor.resume();
    res.status(200).json({ message: "Sessão retomada" });
  });

  router.get("/:id/logs", async (req, res) => {
    const supervisor = sessionManager.requireSession(req.params.id);
    const logs = await logRepository.listRecent(supervisor.sessionId);
    res.json({ logs });
  });

  return router;
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/api"
cat > "src/api/server.ts" << '___CLAUDE_EOF_MARKER___'
import express from "express";
import path from "node:path";
import { env } from "../config/env";
import { SessionManager } from "../sessions/SessionManager";
import { LogRepository } from "../database/repositories/LogRepository";
import { apiKeyAuth } from "./middlewares/auth";
import { apiRateLimiter, platformLoginRateLimiter } from "./middlewares/rateLimiter";
import { errorHandler } from "./middlewares/errorHandler";
import { sessionsRouter } from "./routes/sessions.routes";
import { messagesRouter } from "./routes/messages.routes";
import { healthRouter } from "./routes/health.routes";
import { platformAuthRouter } from "./routes/platform.routes";
import { logger } from "../utils/logger";

export function createServer(sessionManager: SessionManager) {
  const app = express();
  const logRepository = new LogRepository();

  app.use(express.json({ limit: "10mb" }));

  app.get("/", (_req, res) => res.redirect("/platform"));

  // Sem auth por API key: healthcheck do Docker e login da Plataforma
  // (a Plataforma se autentica com sua própria senha, ver platform.routes.ts).
  app.use("/health", healthRouter(sessionManager));
  app.use("/platform/login", platformLoginRateLimiter, platformAuthRouter());

  // Dashboard estático (HTML/JS puro) — servido pelo próprio Controller,
  // sem container/build separado. A autenticação acontece no próprio painel
  // (tela de login chama /platform/login e guarda a API key no navegador).
  app.use("/platform", express.static(path.join(__dirname, "..", "..", "public", "platform")));

  app.use(apiRateLimiter);
  app.use(apiKeyAuth);

  app.use("/sessions", sessionsRouter(sessionManager, logRepository));
  app.use("/sessions", messagesRouter(sessionManager));

  app.use(errorHandler);

  return app;
}

export function startServer(): void {
  const sessionManager = new SessionManager();

  sessionManager
    .initializeAll()
    .then(() => logger.info("SessionManager inicializado"))
    .catch((err) => logger.error({ err }, "Falha ao inicializar sessões"));

  const app = createServer(sessionManager);
  app.listen(env.PORT, () => {
    logger.info({ port: env.PORT }, "API interna no ar");
    logger.info({ url: `http://localhost:${env.PORT}/platform` }, "Plataforma (dashboard) disponível");
  });
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/config"
cat > "src/config/constants.ts" << '___CLAUDE_EOF_MARKER___'
export const WHATSAPP_WEB_URL = "https://web.whatsapp.com";

export const VOLUMES_BASE_PATH = process.env.NODE_ENV === "production" ? "/data/sessions" : "./volumes";

/** Lista realista de viewports para variar por sessão (evita fingerprint idêntico entre contexts) */
export const VIEWPORT_POOL = [
  { width: 1366, height: 768 },
  { width: 1440, height: 900 },
  { width: 1536, height: 864 },
  { width: 1600, height: 900 },
];

/** User agents recentes e plausíveis de desktop (rotação por sessão, não por request) */
export const USER_AGENT_POOL = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
];

export const QR_POLL_INTERVAL_MS = 2000;
export const QR_TIMEOUT_MS = 90_000;

export const RECONNECT_BACKOFF_MS = [5_000, 15_000, 30_000, 60_000, 120_000];

___CLAUDE_EOF_MARKER___

mkdir -p "src/config"
cat > "src/config/env.ts" << '___CLAUDE_EOF_MARKER___'
import dotenv from "dotenv";
import { z } from "zod";

dotenv.config();

const envSchema = z.object({
  PORT: z.coerce.number().default(3000),
  API_KEY: z.string().min(16, "API_KEY deve ter pelo menos 16 caracteres"),
  NODE_ENV: z.enum(["development", "production", "test"]).default("production"),

  REDIS_HOST: z.string().default("redis"),
  REDIS_PORT: z.coerce.number().default(6379),
  REDIS_PASSWORD: z.string().optional().default(""),

  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(10),

  N8N_WEBHOOK_URL: z.string().url(),
  N8N_WEBHOOK_SECRET: z.string().min(8),

  SESSIONS: z.string().optional().default(""),

  PLATFORM_ADMIN_PASSWORD: z.string().min(8, "PLATFORM_ADMIN_PASSWORD deve ter pelo menos 8 caracteres"),

  HUMAN_DELAY_MIN_MS: z.coerce.number().default(1800),
  HUMAN_DELAY_MAX_MS: z.coerce.number().default(6500),
  MAX_MESSAGES_PER_MINUTE: z.coerce.number().default(8),
  WARMUP_PERIOD_HOURS: z.coerce.number().default(48),
  WARMUP_MAX_MESSAGES_PER_MINUTE: z.coerce.number().default(2),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error("Variáveis de ambiente inválidas:", parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;

export type SessionDefinition = {
  id: string;
  name: string;
};

/**
 * Parseia a variável SESSIONS (ex: "01,Vendas;02,Suporte") em uma lista tipada.
 * Este é o único lugar que precisa mudar para ir de 3 para 30/50 sessões:
 * basta editar a variável de ambiente, sem tocar em código.
 */
export function parseSessionDefinitions(raw: string): SessionDefinition[] {
  if (!raw.trim()) return [];
  return raw
    .split(";")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [id, name] = entry.split(",").map((part) => part.trim());
      if (!id || !name) {
        throw new Error(`Entrada inválida em SESSIONS: "${entry}". Formato esperado "id,nome".`);
      }
      return { id, name };
    });
}

/**
 * Semente OPCIONAL para o primeiro boot (ex: "01,Vendas;02,Suporte"). Só é
 * usada se a tabela `sessions` no Supabase estiver vazia — depois disso, a
 * fonte de verdade é o banco, gerenciado pela Plataforma (dashboard) via
 * SessionManager.addSession/removeSession. Pode ficar em branco.
 */
export const sessionDefinitions = parseSessionDefinitions(env.SESSIONS);

___CLAUDE_EOF_MARKER___

mkdir -p "src/database/migrations"
cat > "src/database/migrations/001_init.sql" << '___CLAUDE_EOF_MARKER___'
create table if not exists sessions (
  id text primary key,
  name text not null,
  phone_number text,
  status text not null default 'AGUARDANDO_QR',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  session_id text not null references sessions(id),
  direction text not null check (direction in ('in', 'out')),
  contact text not null,
  type text not null check (type in ('text','image','audio','document','video','other')),
  content_ref text,
  status text not null default 'pending',
  sent_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists logs (
  id uuid primary key default gen_random_uuid(),
  session_id text not null references sessions(id),
  level text not null,
  event text not null,
  message text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create table if not exists queue_metrics (
  id uuid primary key default gen_random_uuid(),
  session_id text not null references sessions(id),
  queue_size integer not null default 0,
  processed_count integer not null default 0,
  error_count integer not null default 0,
  captured_at timestamptz not null default now()
);

create index if not exists idx_messages_session on messages(session_id);
create index if not exists idx_logs_session on logs(session_id);
create index if not exists idx_queue_metrics_session on queue_metrics(session_id);

___CLAUDE_EOF_MARKER___

mkdir -p "src/database/repositories"
cat > "src/database/repositories/LogRepository.ts" << '___CLAUDE_EOF_MARKER___'
import { supabase } from "../supabaseClient";
import { logger } from "../../utils/logger";

export class LogRepository {
  async record(sessionId: string, level: "info" | "warn" | "error", event: string, message: string): Promise<void> {
    const { error } = await supabase.from("logs").insert({
      session_id: sessionId,
      level,
      event,
      message,
    });

    if (error) {
      // Nunca deixar falha de log derrubar o fluxo principal — apenas loga localmente.
      logger.error({ error, sessionId, event }, "Falha ao gravar log no Supabase");
    }
  }

  async listRecent(sessionId: string, limit = 100) {
    const { data, error } = await supabase
      .from("logs")
      .select("*")
      .eq("session_id", sessionId)
      .order("created_at", { ascending: false })
      .limit(limit);

    if (error) {
      logger.error({ error, sessionId }, "Falha ao listar logs");
      return [];
    }
    return data;
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/database/repositories"
cat > "src/database/repositories/MessageRepository.ts" << '___CLAUDE_EOF_MARKER___'
import { supabase } from "../supabaseClient";
import { logger } from "../../utils/logger";

export class MessageRepository {
  async recordSent(sessionId: string, contact: string, type: string, status: "success" | "error"): Promise<void> {
    const { error } = await supabase.from("messages").insert({
      session_id: sessionId,
      direction: "out",
      contact,
      type,
      status,
      sent_at: new Date().toISOString(),
    });
    if (error) logger.error({ error, sessionId }, "Falha ao registrar mensagem enviada");
  }

  async recordReceived(sessionId: string, contact: string, type: string, content: string): Promise<void> {
    const { error } = await supabase.from("messages").insert({
      session_id: sessionId,
      direction: "in",
      contact,
      type,
      content_ref: content,
      status: "received",
      received_at: new Date().toISOString(),
    });
    if (error) logger.error({ error, sessionId }, "Falha ao registrar mensagem recebida");
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/database/repositories"
cat > "src/database/repositories/SessionRepository.ts" << '___CLAUDE_EOF_MARKER___'
import { supabase } from "../supabaseClient";
import { logger } from "../../utils/logger";

export interface SessionRecord {
  id: string;
  name: string;
  phone_number: string | null;
  status: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

/**
 * Fonte da verdade sobre QUAIS sessões existem. Antes, essa lista vinha fixa
 * da variável de ambiente SESSIONS — qualquer número novo exigia redeploy.
 * Agora a Plataforma (dashboard) cria/remove registros aqui, e o
 * SessionManager lê esta tabela na inicialização e reage a mudanças em
 * tempo real via os métodos addSession/removeSession.
 */
export class SessionRepository {
  async listActive(): Promise<SessionRecord[]> {
    const { data, error } = await supabase.from("sessions").select("*").eq("active", true).order("created_at");
    if (error) {
      logger.error({ error }, "Falha ao listar sessões ativas no Supabase");
      return [];
    }
    return data as SessionRecord[];
  }

  async create(id: string, name: string): Promise<void> {
    const { error } = await supabase.from("sessions").insert({ id, name, status: "AGUARDANDO_QR", active: true });
    if (error) throw new Error(`Falha ao criar sessão no banco: ${error.message}`);
  }

  async updateStatus(id: string, status: string): Promise<void> {
    const { error } = await supabase
      .from("sessions")
      .update({ status, updated_at: new Date().toISOString() })
      .eq("id", id);
    if (error) logger.error({ error, id }, "Falha ao atualizar status da sessão no Supabase");
  }

  async updatePhoneNumber(id: string, phoneNumber: string): Promise<void> {
    const { error } = await supabase.from("sessions").update({ phone_number: phoneNumber }).eq("id", id);
    if (error) logger.error({ error, id }, "Falha ao atualizar número da sessão");
  }

  async deactivate(id: string): Promise<void> {
    const { error } = await supabase.from("sessions").update({ active: false }).eq("id", id);
    if (error) throw new Error(`Falha ao desativar sessão no banco: ${error.message}`);
  }

  async exists(id: string): Promise<boolean> {
    const { data, error } = await supabase.from("sessions").select("id").eq("id", id).maybeSingle();
    if (error) {
      logger.error({ error, id }, "Falha ao checar existência da sessão");
      return false;
    }
    return !!data;
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/database"
cat > "src/database/supabaseClient.ts" << '___CLAUDE_EOF_MARKER___'
import { createClient } from "@supabase/supabase-js";
import { env } from "../config/env";

export const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

___CLAUDE_EOF_MARKER___

mkdir -p "src"
cat > "src/index.ts" << '___CLAUDE_EOF_MARKER___'
import { startServer } from "./api/server";
import { logger } from "./utils/logger";

process.on("unhandledRejection", (reason) => {
  logger.error({ reason }, "Unhandled promise rejection");
});

process.on("uncaughtException", (err) => {
  logger.error({ err }, "Uncaught exception");
});

startServer();

___CLAUDE_EOF_MARKER___

mkdir -p "src/playwright"
cat > "src/playwright/BrowserDriver.ts" << '___CLAUDE_EOF_MARKER___'
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

___CLAUDE_EOF_MARKER___

mkdir -p "src/playwright"
cat > "src/playwright/PlaywrightDriver.ts" << '___CLAUDE_EOF_MARKER___'
import path from "node:path";
import { chromium, BrowserContext, Page } from "playwright";
import { IBrowserDriver, SendTextParams, SendMediaParams, IncomingMessage } from "./BrowserDriver";
import { WhatsAppSelectors } from "./selectors/whatsappSelectors";
import { getStableFingerprint, hardenContext, RECOMMENDED_LAUNCH_ARGS } from "./antiDetection";
import { humanDelay, humanType, simulatePresence, microDelay } from "../utils/humanBehavior";
import { VOLUMES_BASE_PATH, WHATSAPP_WEB_URL, QR_TIMEOUT_MS } from "../config/constants";
import { logger } from "../utils/logger";
import { attachIncomingMessageListener } from "./listeners/incomingMessageListener";

interface SessionRuntime {
  context: BrowserContext;
  page: Page;
  lastQr: string | null;
  connected: boolean;
  incomingHandlers: Array<(msg: IncomingMessage) => void>;
  disconnectHandlers: Array<() => void>;
}

/**
 * Implementação real do IBrowserDriver usando Playwright + Chromium.
 * Cada sessão = 1 BrowserContext PERSISTENTE (perfil próprio em disco),
 * garantindo que reiniciar o container não derrube o login (requisito
 * de persistência) e que cada sessão tenha fingerprint estável (antiDetection).
 */
export class PlaywrightDriver implements IBrowserDriver {
  private sessions = new Map<string, SessionRuntime>();

  private profileDir(sessionId: string): string {
    return path.join(VOLUMES_BASE_PATH, `session-${sessionId}`, "profile");
  }

  async startSession(sessionId: string): Promise<void> {
    if (this.sessions.has(sessionId)) {
      logger.warn({ sessionId }, "Sessão já iniciada, ignorando novo start");
      return;
    }

    const { viewport, userAgent } = getStableFingerprint(sessionId);

    const context = await chromium.launchPersistentContext(this.profileDir(sessionId), {
      headless: true,
      viewport,
      userAgent,
      locale: "pt-BR",
      timezoneId: "America/Cuiaba",
      args: RECOMMENDED_LAUNCH_ARGS,
    });

    await hardenContext(context);

    const page = context.pages()[0] ?? (await context.newPage());

    const runtime: SessionRuntime = {
      context,
      page,
      lastQr: null,
      connected: false,
      incomingHandlers: [],
      disconnectHandlers: [],
    };
    this.sessions.set(sessionId, runtime);

    await page.goto(WHATSAPP_WEB_URL, { waitUntil: "domcontentloaded" });
    await simulatePresence(page);

    await this.watchForQrOrLoad(sessionId, runtime);
    await this.attachIncomingMessageListener(sessionId, runtime);
    this.attachDisconnectionWatcher(sessionId, runtime);

    logger.info({ sessionId }, "Sessão iniciada");
  }

  async stopSession(sessionId: string): Promise<void> {
    const runtime = this.sessions.get(sessionId);
    if (!runtime) return;
    await runtime.context.close();
    this.sessions.delete(sessionId);
    logger.info({ sessionId }, "Sessão finalizada");
  }

  async getQrCode(sessionId: string): Promise<string | null> {
    return this.sessions.get(sessionId)?.lastQr ?? null;
  }

  async isConnected(sessionId: string): Promise<boolean> {
    return this.sessions.get(sessionId)?.connected ?? false;
  }

  onIncomingMessage(sessionId: string, handler: (msg: IncomingMessage) => void): void {
    const runtime = this.sessions.get(sessionId);
    runtime?.incomingHandlers.push(handler);
  }

  onDisconnected(sessionId: string, handler: () => void): void {
    const runtime = this.sessions.get(sessionId);
    runtime?.disconnectHandlers.push(handler);
  }

  async sendText({ sessionId, contact, text }: SendTextParams): Promise<void> {
    const runtime = this.requireRuntime(sessionId);
    const { page } = runtime;

    await this.openChat(page, contact);
    await simulatePresence(page);
    await humanDelay();

    await humanType(page, WhatsAppSelectors.messageInput, text);
    await microDelay(150, 400);
    await page.locator(WhatsAppSelectors.sendButton).click();

    logger.info({ sessionId, contact }, "Mensagem de texto enviada");
  }

  async sendImage(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "image");
  }

  async sendAudio(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "audio");
  }

  async sendDocument(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "document");
  }

  async sendVideo(params: SendMediaParams): Promise<void> {
    await this.sendMedia(params, "video");
  }

  // ---------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------

  private requireRuntime(sessionId: string): SessionRuntime {
    const runtime = this.sessions.get(sessionId);
    if (!runtime) {
      throw new Error(`Sessão ${sessionId} não está ativa. Chame startSession primeiro.`);
    }
    return runtime;
  }

  private async openChat(page: Page, contact: string): Promise<void> {
    await page.locator(WhatsAppSelectors.chatSearchInput).click();
    await humanType(page, WhatsAppSelectors.chatSearchInput, contact);
    await microDelay(400, 900);
    await page.keyboard.press("Enter");
    await microDelay(300, 700);
  }

  private async sendMedia(
    { sessionId, contact, filePath, caption }: SendMediaParams,
    _kind: "image" | "audio" | "document" | "video"
  ): Promise<void> {
    const runtime = this.requireRuntime(sessionId);
    const { page } = runtime;

    await this.openChat(page, contact);
    await simulatePresence(page);
    await humanDelay();

    await page.locator(WhatsAppSelectors.attachButton).click();
    await microDelay(200, 500);

    const fileInput = page.locator(WhatsAppSelectors.attachDocumentInput).first();
    await fileInput.setInputFiles(filePath);
    await microDelay(500, 1200);

    if (caption) {
      await humanType(page, WhatsAppSelectors.messageInput, caption);
    }

    await microDelay(150, 400);
    await page.locator(WhatsAppSelectors.sendButton).click();

    logger.info({ sessionId, contact, filePath }, "Mídia enviada");
  }

  private async watchForQrOrLoad(sessionId: string, runtime: SessionRuntime): Promise<void> {
    const { page } = runtime;
    const deadline = Date.now() + QR_TIMEOUT_MS;

    while (Date.now() < deadline) {
      const appLoaded = await page.locator(WhatsAppSelectors.appLoaded).count();
      if (appLoaded > 0) {
        runtime.connected = true;
        runtime.lastQr = null;
        return;
      }

      const qrCanvas = page.locator(WhatsAppSelectors.qrCodeCanvas);
      if ((await qrCanvas.count()) > 0) {
        try {
          const qrDataUrl = await qrCanvas.evaluate((el) => (el as HTMLCanvasElement).toDataURL());
          runtime.lastQr = qrDataUrl;
        } catch {
          // canvas pode estar re-renderizando; tenta de novo no próximo loop
        }
      }

      await microDelay(1000, 1500);
    }

    logger.warn({ sessionId }, "Timeout aguardando QR code / carregamento da sessão");
  }

  private async attachIncomingMessageListener(sessionId: string, runtime: SessionRuntime): Promise<void> {
    try {
      await attachIncomingMessageListener(runtime.page, sessionId, (msg) => {
        runtime.incomingHandlers.forEach((handler) => handler(msg));
      });
    } catch (error) {
      // Falha ao anexar o listener não deve derrubar a sessão inteira — o envio
      // continua funcionando, só o recebimento automático fica indisponível
      // até o próximo restart. Loga como erro para investigação.
      logger.error({ sessionId, error }, "Falha ao anexar listener de mensagens recebidas");
    }
  }

  private attachDisconnectionWatcher(sessionId: string, runtime: SessionRuntime): void {
    runtime.page.on("close", () => {
      runtime.connected = false;
      runtime.disconnectHandlers.forEach((h) => h());
      logger.warn({ sessionId }, "Página da sessão fechou inesperadamente");
    });
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/playwright"
cat > "src/playwright/antiDetection.ts" << '___CLAUDE_EOF_MARKER___'
import { BrowserContext } from "playwright";
import { USER_AGENT_POOL, VIEWPORT_POOL } from "../config/constants";

/**
 * Escolhe, de forma DETERMINÍSTICA por sessão (mesma sessão sempre pega o mesmo
 * perfil), um viewport e user-agent do pool. Determinístico é importante: uma
 * sessão que muda de fingerprint a cada restart é, ironicamente, MAIS suspeita
 * que uma com identidade estável — o objetivo é parecer um usuário real com um
 * computador real, não uma sessão nova a cada boot.
 */
function pickStableFromPool<T>(pool: T[], sessionId: string): T {
  let hash = 0;
  for (let i = 0; i < sessionId.length; i++) {
    hash = (hash * 31 + sessionId.charCodeAt(i)) >>> 0;
  }
  return pool[hash % pool.length];
}

export function getStableFingerprint(sessionId: string) {
  return {
    viewport: pickStableFromPool(VIEWPORT_POOL, sessionId),
    userAgent: pickStableFromPool(USER_AGENT_POOL, sessionId),
  };
}

/**
 * Aplica scripts de inicialização no contexto para reduzir sinais óbvios de
 * automação (ex.: navigator.webdriver = true é o sinal mais básico e comum
 * checado por qualquer sistema anti-bot). Isso NÃO desativa nenhuma checagem
 * de segurança do WhatsApp nem contorna autenticação — apenas evita o sinal
 * mais grosseiro de "isto é o Chromium controlado por automação".
 */
export async function hardenContext(context: BrowserContext): Promise<void> {
  await context.addInitScript(() => {
    Object.defineProperty(navigator, "webdriver", { get: () => undefined });

    // Alguns sistemas checam plugins/mimeTypes vazios como sinal de headless.
    Object.defineProperty(navigator, "plugins", {
      get: () => [1, 2, 3, 4, 5],
    });
    Object.defineProperty(navigator, "languages", {
      get: () => ["pt-BR", "pt", "en-US", "en"],
    });

    // window.chrome ausente é outro sinal comum em Chromium automatizado.
    // @ts-expect-error - propriedade não tipada no lib.dom
    if (!window.chrome) {
      // @ts-expect-error - propriedade não tipada no lib.dom
      window.chrome = { runtime: {} };
    }
  });
}

/**
 * Opções recomendadas de launch para reduzir superfícies de detecção óbvias.
 * Mantém headless configurável — para ambientes de VPS sem GPU, headless "new"
 * costuma ser suficiente combinado com o hardening acima.
 */
export const RECOMMENDED_LAUNCH_ARGS = [
  "--disable-blink-features=AutomationControlled",
  "--disable-features=IsolateOrigins,site-per-process",
  "--no-sandbox",
  "--disable-dev-shm-usage",
];

___CLAUDE_EOF_MARKER___

mkdir -p "src/playwright/listeners"
cat > "src/playwright/listeners/incomingMessageListener.ts" << '___CLAUDE_EOF_MARKER___'
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

___CLAUDE_EOF_MARKER___

mkdir -p "src/playwright/selectors"
cat > "src/playwright/selectors/whatsappSelectors.ts" << '___CLAUDE_EOF_MARKER___'
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
  appLoaded: 'div[id="app"]',
  chatSearchInput: 'div[contenteditable="true"][data-tab="3"], div[aria-label="Search input textbox"]',
  messageInput: 'div[contenteditable="true"][data-tab="10"], footer div[contenteditable="true"]',
  sendButton: 'button[aria-label="Send"]',
  attachButton: 'div[title="Attach"], button[aria-label="Attach"]',
  attachImageInput: 'input[accept*="image"]',
  attachDocumentInput: 'input[accept*="*"]',
  incomingMessageBubble: 'div[data-testid="msg-container"], div.message-in',
  disconnectedBanner: 'div[data-testid="alert-phone"], div[data-ref]',
} as const;

___CLAUDE_EOF_MARKER___

mkdir -p "src/queue"
cat > "src/queue/QueueManager.ts" << '___CLAUDE_EOF_MARKER___'
import { Queue, ConnectionOptions } from "bullmq";
import { env } from "../config/env";
import { computeMinIntervalMs } from "../utils/humanBehavior";

export interface SendMessageJobData {
  sessionId: string;
  contact: string;
  type: "text" | "image" | "audio" | "document" | "video";
  payload: Record<string, unknown>;
}

/**
 * Uma fila Redis (BullMQ) por sessão. O rate limit do BullMQ é configurado
 * dinamicamente por sessão com base no período de "aquecimento" — sessões
 * recém-criadas têm limite de envio bem mais conservador (ver
 * utils/humanBehavior.computeMinIntervalMs), reduzindo o principal gatilho
 * de banimento: volume alto vindo de um número "novo".
 *
 * Passamos apenas as OPÇÕES de conexão (não uma instância de ioredis criada
 * por nós) para o BullMQ — isso evita conflito de tipos entre a versão do
 * ioredis do projeto e a versão interna que o BullMQ empacota, e deixa o
 * BullMQ gerenciar seu próprio ciclo de vida de conexão.
 */
export class QueueManager {
  private connection: ConnectionOptions;
  private queues = new Map<string, Queue<SendMessageJobData>>();

  constructor() {
    this.connection = {
      host: env.REDIS_HOST,
      port: env.REDIS_PORT,
      password: env.REDIS_PASSWORD || undefined,
      maxRetriesPerRequest: null,
    };
  }

  getOrCreateQueue(sessionId: string, sessionCreatedAt: Date): Queue<SendMessageJobData> {
    const existing = this.queues.get(sessionId);
    if (existing) return existing;

    const queue = new Queue<SendMessageJobData>(`session:${sessionId}`, {
      connection: this.connection,
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: "exponential", delay: 5000 },
        removeOnComplete: 200,
        removeOnFail: 500,
      },
    });

    // Guardamos a data de criação junto ao queue para recalcular o limiter
    // dinamicamente (o intervalo mínimo aumenta conforme a sessão "amadurece").
    (queue as unknown as { __sessionCreatedAt: Date }).__sessionCreatedAt = sessionCreatedAt;

    this.queues.set(sessionId, queue);
    return queue;
  }

  /** Intervalo mínimo atual (ms) entre jobs desta sessão, recalculado a cada chamada. */
  getCurrentMinIntervalMs(sessionId: string): number {
    const queue = this.queues.get(sessionId);
    const createdAt = (queue as unknown as { __sessionCreatedAt?: Date })?.__sessionCreatedAt ?? new Date();
    return computeMinIntervalMs(createdAt);
  }

  async enqueue(sessionId: string, sessionCreatedAt: Date, data: SendMessageJobData): Promise<string> {
    const queue = this.getOrCreateQueue(sessionId, sessionCreatedAt);
    const job = await queue.add("send-message", data, {
      // O delay real de processamento humano/orgânico é aplicado no worker
      // (ver QueueWorker), este é só o enfileiramento.
    });
    return job.id ?? "";
  }

  async clear(sessionId: string): Promise<void> {
    const queue = this.queues.get(sessionId);
    if (!queue) return;
    await queue.drain();
  }

  async getQueueSize(sessionId: string): Promise<number> {
    const queue = this.queues.get(sessionId);
    if (!queue) return 0;
    return queue.count();
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/queue"
cat > "src/queue/QueueWorker.ts" << '___CLAUDE_EOF_MARKER___'
import { Worker, Job, ConnectionOptions } from "bullmq";
import { env } from "../config/env";
import { SendMessageJobData } from "./QueueManager";
import { IBrowserDriver } from "../playwright/BrowserDriver";
import { WebhookDispatcher } from "../webhooks/WebhookDispatcher";
import { LogRepository } from "../database/repositories/LogRepository";
import { MessageRepository } from "../database/repositories/MessageRepository";
import { computeMinIntervalMs, sleep } from "../utils/humanBehavior";
import { childLogger } from "../utils/logger";

/**
 * Um worker por sessão, com `concurrency: 1` — garante que NUNCA duas
 * mensagens da mesma sessão sejam processadas ao mesmo tempo (requisito
 * de negócio) e, junto com o delay mínimo dinâmico, mantém o volume de
 * envio dentro de um padrão que se assemelha a uso humano.
 */
export function createSessionWorker(
  sessionId: string,
  sessionCreatedAt: Date,
  driver: IBrowserDriver,
  webhookDispatcher: WebhookDispatcher,
  logRepository: LogRepository,
  messageRepository: MessageRepository
): Worker<SendMessageJobData> {
  const log = childLogger(sessionId);

  const connection: ConnectionOptions = {
    host: env.REDIS_HOST,
    port: env.REDIS_PORT,
    password: env.REDIS_PASSWORD || undefined,
    maxRetriesPerRequest: null,
  };

  const worker = new Worker<SendMessageJobData>(
    `session:${sessionId}`,
    async (job: Job<SendMessageJobData>) => {
      const { contact, type, payload } = job.data;

      // Respiro mínimo antes de processar o próximo job — mesmo que a fila
      // esteja cheia, isso impede rajadas de mensagens em sequência.
      const minInterval = computeMinIntervalMs(sessionCreatedAt);
      await sleep(minInterval);

      try {
        switch (type) {
          case "text":
            await driver.sendText({ sessionId, contact, text: payload.text as string });
            break;
          case "image":
            await driver.sendImage({ sessionId, contact, filePath: payload.filePath as string, caption: payload.caption as string | undefined });
            break;
          case "audio":
            await driver.sendAudio({ sessionId, contact, filePath: payload.filePath as string });
            break;
          case "document":
            await driver.sendDocument({ sessionId, contact, filePath: payload.filePath as string, caption: payload.caption as string | undefined });
            break;
          case "video":
            await driver.sendVideo({ sessionId, contact, filePath: payload.filePath as string, caption: payload.caption as string | undefined });
            break;
        }

        await messageRepository.recordSent(sessionId, contact, type, "success");
        await webhookDispatcher.emit("message.sent", { sessionId, jobId: job.id, contact, type, status: "success" });
      } catch (error) {
        log.error({ error, jobId: job.id }, "Falha ao processar job de envio");
        await messageRepository.recordSent(sessionId, contact, type, "error");
        await logRepository.record(sessionId, "error", "send_failed", String(error));
        await webhookDispatcher.emit("message.sent", { sessionId, jobId: job.id, contact, type, status: "error" });
        throw error; // deixa o BullMQ aplicar o retry configurado na fila
      }
    },
    {
      connection,
      concurrency: 1, // trava dura: nunca 2 mensagens simultâneas na mesma sessão
      limiter: {
        max: 1,
        duration: computeMinIntervalMs(sessionCreatedAt),
      },
    }
  );

  worker.on("failed", (job, err) => {
    log.error({ jobId: job?.id, err }, "Job falhou definitivamente após retries");
  });

  return worker;
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/sessions"
cat > "src/sessions/SessionManager.ts" << '___CLAUDE_EOF_MARKER___'
import { sessionDefinitions } from "../config/env";
import { PlaywrightDriver } from "../playwright/PlaywrightDriver";
import { SessionSupervisor } from "./SessionSupervisor";
import { LogRepository } from "../database/repositories/LogRepository";
import { MessageRepository } from "../database/repositories/MessageRepository";
import { SessionRepository } from "../database/repositories/SessionRepository";
import { WebhookDispatcher } from "../webhooks/WebhookDispatcher";
import { QueueManager } from "../queue/QueueManager";
import { createSessionWorker } from "../queue/QueueWorker";
import { Worker } from "bullmq";
import { logger } from "../utils/logger";

/**
 * Ponto único de criação/listagem/controle das sessões — agora DINÂMICO.
 *
 * Antes: a lista de sessões vinha fixa de uma variável de ambiente, exigindo
 * redeploy para adicionar um número novo.
 *
 * Agora: o Supabase (`sessions`) é a fonte de verdade. Na inicialização, o
 * SessionManager lê a tabela; se estiver vazia, semeia com SESSIONS do .env
 * (só para facilitar o primeiro boot). Depois disso, números são
 * adicionados/removidos em tempo real pela Plataforma (dashboard), via
 * addSession()/removeSession(), sem reiniciar o container.
 */
export class SessionManager {
  private supervisors = new Map<string, SessionSupervisor>();
  private workers = new Map<string, Worker>();
  private readonly driver = new PlaywrightDriver();
  private readonly logRepository = new LogRepository();
  private readonly messageRepository = new MessageRepository();
  private readonly webhookDispatcher = new WebhookDispatcher();
  private readonly sessionRepository = new SessionRepository();
  private readonly queueManager = new QueueManager();

  async initializeAll(): Promise<void> {
    let records = await this.sessionRepository.listActive();

    if (records.length === 0 && sessionDefinitions.length > 0) {
      logger.info({ count: sessionDefinitions.length }, "Tabela sessions vazia — semeando a partir do .env");
      for (const def of sessionDefinitions) {
        await this.sessionRepository.create(def.id, def.name);
      }
      records = await this.sessionRepository.listActive();
    }

    // Stagger entre inicializações: sessões não sobem todas no mesmo instante
    // (reduz padrão de uso robótico e picos de carga na VPS).
    await Promise.allSettled(
      records.map(async (record) => {
        const staggerMs = Math.random() * 4000;
        await new Promise((r) => setTimeout(r, staggerMs));
        await this.bootSession(record.id, record.name);
      })
    );

    logger.info({ total: this.supervisors.size }, "Todas as sessões foram inicializadas (ou tentaram ser)");
  }

  /**
   * Cria uma sessão nova via Plataforma: grava no Supabase, sobe o supervisor
   * e o worker da fila, e retorna imediatamente — o QR code fica disponível
   * em poucos segundos via GET /sessions/:id/qrcode.
   */
  async addSession(id: string, name: string): Promise<SessionSupervisor> {
    if (this.supervisors.has(id)) {
      throw new Error(`Sessão "${id}" já existe`);
    }
    const alreadyInDb = await this.sessionRepository.exists(id);
    if (alreadyInDb) {
      throw new Error(`Já existe uma sessão com o id "${id}" no banco (pode estar inativa)`);
    }

    await this.sessionRepository.create(id, name);
    const supervisor = await this.bootSession(id, name);
    logger.info({ id, name }, "Nova sessão criada pela Plataforma");
    return supervisor;
  }

  /** Remove uma sessão: para o navegador, o worker, e desativa o registro (soft delete). */
  async removeSession(id: string): Promise<void> {
    const supervisor = this.requireSession(id);
    await supervisor.stop();

    const worker = this.workers.get(id);
    if (worker) {
      await worker.close();
      this.workers.delete(id);
    }
    await this.queueManager.clear(id);

    this.supervisors.delete(id);
    await this.sessionRepository.deactivate(id);
    logger.info({ id }, "Sessão removida pela Plataforma");
  }

  private async bootSession(id: string, name: string): Promise<SessionSupervisor> {
    const supervisor = new SessionSupervisor(
      id,
      name,
      this.driver,
      this.logRepository,
      this.webhookDispatcher,
      this.messageRepository,
      this.sessionRepository
    );
    this.supervisors.set(id, supervisor);

    const worker = createSessionWorker(
      id,
      supervisor.getCreatedAt(),
      this.driver,
      this.webhookDispatcher,
      this.logRepository,
      this.messageRepository
    );
    this.workers.set(id, worker);

    await supervisor.start();
    return supervisor;
  }

  get(sessionId: string): SessionSupervisor | undefined {
    return this.supervisors.get(sessionId);
  }

  requireSession(sessionId: string): SessionSupervisor {
    const supervisor = this.supervisors.get(sessionId);
    if (!supervisor) {
      throw new Error(`Sessão "${sessionId}" não encontrada`);
    }
    return supervisor;
  }

  list(): SessionSupervisor[] {
    return Array.from(this.supervisors.values());
  }

  getQueueManager(): QueueManager {
    return this.queueManager;
  }

  async getQrCode(sessionId: string): Promise<string | null> {
    this.requireSession(sessionId); // valida existência, lança se não encontrada
    return this.driver.getQrCode(sessionId);
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/sessions"
cat > "src/sessions/SessionState.ts" << '___CLAUDE_EOF_MARKER___'
export enum SessionState {
  AGUARDANDO_QR = "AGUARDANDO_QR",
  CONECTANDO = "CONECTANDO",
  CONECTADO = "CONECTADO",
  DESCONECTADO = "DESCONECTADO",
  REINICIANDO = "REINICIANDO",
  PAUSADO = "PAUSADO",
  ERRO = "ERRO",
}

/** Transições permitidas — qualquer transição fora desta tabela deve ser rejeitada e logada como anomalia. */
export const ALLOWED_TRANSITIONS: Record<SessionState, SessionState[]> = {
  [SessionState.AGUARDANDO_QR]: [SessionState.CONECTANDO, SessionState.ERRO],
  [SessionState.CONECTANDO]: [SessionState.CONECTADO, SessionState.AGUARDANDO_QR, SessionState.ERRO],
  [SessionState.CONECTADO]: [SessionState.DESCONECTADO, SessionState.PAUSADO, SessionState.ERRO],
  [SessionState.DESCONECTADO]: [SessionState.REINICIANDO, SessionState.ERRO],
  [SessionState.REINICIANDO]: [SessionState.AGUARDANDO_QR, SessionState.CONECTANDO, SessionState.ERRO],
  [SessionState.PAUSADO]: [SessionState.CONECTADO, SessionState.REINICIANDO],
  [SessionState.ERRO]: [SessionState.REINICIANDO],
};

export function canTransition(from: SessionState, to: SessionState): boolean {
  return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/sessions"
cat > "src/sessions/SessionSupervisor.ts" << '___CLAUDE_EOF_MARKER___'
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
    private readonly sessionRepository: SessionRepository
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

___CLAUDE_EOF_MARKER___

mkdir -p "src/utils"
cat > "src/utils/humanBehavior.ts" << '___CLAUDE_EOF_MARKER___'
import { Page } from "playwright";
import { env } from "../config/env";

/**
 * Camada de "comportamento humano" usada por toda ação que mexe no navegador.
 * Objetivo: reduzir a chance de detecção/banimento por padrão de automação,
 * SEM burlar nenhum mecanismo de segurança do WhatsApp — apenas evitando
 * um padrão de uso obviamente robótico (cadência perfeita, digitação instantânea,
 * zero variação de tempo entre ações).
 */

export function randomBetween(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Delay "humano" entre ações consecutivas na mesma sessão. */
export async function humanDelay(): Promise<void> {
  const ms = randomBetween(env.HUMAN_DELAY_MIN_MS, env.HUMAN_DELAY_MAX_MS);
  await sleep(ms);
}

/** Pequena variação para não repetir exatamente o mesmo delay em ações internas (ex: entre teclas). */
export async function microDelay(minMs = 40, maxMs = 180): Promise<void> {
  await sleep(randomBetween(minMs, maxMs));
}

/**
 * Digita texto em um campo simulando velocidade humana (não usa fill() instantâneo),
 * com pequenas variações de intervalo entre caracteres.
 */
export async function humanType(page: Page, selector: string, text: string): Promise<void> {
  const locator = page.locator(selector);
  await locator.click();
  for (const char of text) {
    await locator.pressSequentially(char, { delay: randomBetween(35, 140) });
    // ocasionalmente uma pausa maior, como alguém pensando
    if (Math.random() < 0.05) {
      await microDelay(200, 600);
    }
  }
}

/**
 * Scroll leve e movimento de mouse antes de uma ação, para gerar eventos de input
 * mais próximos de uso real (o WhatsApp Web, como muitos sistemas anti-bot,
 * observa presença de eventos de mouse/scroll, não só cliques secos).
 */
export async function simulatePresence(page: Page): Promise<void> {
  try {
    const viewport = page.viewportSize();
    if (!viewport) return;
    const x = randomBetween(50, viewport.width - 50);
    const y = randomBetween(50, viewport.height - 50);
    await page.mouse.move(x, y, { steps: randomBetween(5, 15) });
    await microDelay(100, 400);
  } catch {
    // não crítico — se falhar, apenas segue sem simular presença
  }
}

/**
 * Calcula o intervalo mínimo (ms) entre envios de mensagem para uma sessão,
 * respeitando o limite configurado e um período de "aquecimento" para sessões novas.
 */
export function computeMinIntervalMs(sessionCreatedAt: Date): number {
  const hoursSinceCreation = (Date.now() - sessionCreatedAt.getTime()) / (1000 * 60 * 60);
  const isWarmingUp = hoursSinceCreation < env.WARMUP_PERIOD_HOURS;
  const maxPerMinute = isWarmingUp ? env.WARMUP_MAX_MESSAGES_PER_MINUTE : env.MAX_MESSAGES_PER_MINUTE;
  return Math.ceil(60_000 / Math.max(maxPerMinute, 1));
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/utils"
cat > "src/utils/logger.ts" << '___CLAUDE_EOF_MARKER___'
import pino from "pino";
import { env } from "../config/env";

export const logger = pino({
  level: env.NODE_ENV === "production" ? "info" : "debug",
  transport:
    env.NODE_ENV !== "production"
      ? { target: "pino-pretty", options: { colorize: true, translateTime: "SYS:standard" } }
      : undefined,
  base: { service: "whatsapp-browser-controller" },
});

export function childLogger(sessionId: string) {
  return logger.child({ sessionId });
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/utils"
cat > "src/utils/retry.ts" << '___CLAUDE_EOF_MARKER___'
export interface RetryOptions {
  attempts?: number;
  baseDelayMs?: number;
  onRetry?: (error: unknown, attempt: number) => void;
}

/**
 * Retry com backoff exponencial + jitter. Usado em ações de navegador
 * (que podem falhar por lentidão de render) e em chamadas de webhook.
 */
export async function withRetry<T>(fn: () => Promise<T>, options: RetryOptions = {}): Promise<T> {
  const { attempts = 3, baseDelayMs = 1000, onRetry } = options;
  let lastError: unknown;

  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      onRetry?.(error, attempt);
      if (attempt < attempts) {
        const jitter = Math.random() * 300;
        const delay = baseDelayMs * 2 ** (attempt - 1) + jitter;
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError;
}

___CLAUDE_EOF_MARKER___

mkdir -p "src/webhooks"
cat > "src/webhooks/WebhookDispatcher.ts" << '___CLAUDE_EOF_MARKER___'
import { env } from "../config/env";
import { withRetry } from "../utils/retry";
import { logger } from "../utils/logger";

type EventName =
  | "session.status_changed"
  | "message.received"
  | "message.sent"
  | "session.qr_updated"
  | "session.error";

/**
 * Envia eventos para o webhook do n8n. Se o n8n estiver fora do ar, os eventos
 * pendentes ficam em uma fila em memória simples e são reenviados em segundo
 * plano — para volume alto/produção crítica, trocar por uma fila Redis dedicada
 * (mesmo padrão do QueueManager), mas para o MVP isso já evita perda de eventos
 * em quedas curtas do n8n.
 */
export class WebhookDispatcher {
  private pending: Array<{ event: EventName; payload: unknown; attempts: number }> = [];
  private flushing = false;

  async emit(event: EventName, payload: unknown): Promise<void> {
    try {
      await withRetry(() => this.send(event, payload), {
        attempts: 3,
        baseDelayMs: 1000,
        onRetry: (err, attempt) => logger.warn({ err, attempt, event }, "Retry ao enviar webhook"),
      });
    } catch (error) {
      logger.error({ error, event }, "Falha definitiva ao enviar webhook, guardando para retry posterior");
      this.pending.push({ event, payload, attempts: 0 });
      this.scheduleFlush();
    }
  }

  private async send(event: EventName, payload: unknown): Promise<void> {
    const response = await fetch(env.N8N_WEBHOOK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Webhook-Secret": env.N8N_WEBHOOK_SECRET,
      },
      body: JSON.stringify({ event, payload, emittedAt: new Date().toISOString() }),
    });

    if (!response.ok) {
      throw new Error(`Webhook respondeu com status ${response.status}`);
    }
  }

  private scheduleFlush(): void {
    if (this.flushing) return;
    this.flushing = true;
    setTimeout(async () => {
      await this.flushPending();
      this.flushing = false;
      if (this.pending.length > 0) this.scheduleFlush();
    }, 15_000);
  }

  private async flushPending(): Promise<void> {
    const batch = [...this.pending];
    this.pending = [];
    for (const item of batch) {
      try {
        await this.send(item.event, item.payload);
      } catch {
        item.attempts++;
        if (item.attempts < 5) this.pending.push(item);
        else logger.error({ item }, "Evento de webhook descartado após múltiplas falhas");
      }
    }
  }
}

___CLAUDE_EOF_MARKER___

mkdir -p "tests/unit"
cat > "tests/unit/SessionState.test.ts" << '___CLAUDE_EOF_MARKER___'
import { describe, it, expect } from "vitest";
import { SessionState, canTransition } from "../../src/sessions/SessionState";

describe("SessionState transitions", () => {
  it("permite transição de AGUARDANDO_QR para CONECTANDO", () => {
    expect(canTransition(SessionState.AGUARDANDO_QR, SessionState.CONECTANDO)).toBe(true);
  });

  it("bloqueia transição direta de AGUARDANDO_QR para CONECTADO", () => {
    expect(canTransition(SessionState.AGUARDANDO_QR, SessionState.CONECTADO)).toBe(false);
  });

  it("permite reconexão de DESCONECTADO para REINICIANDO", () => {
    expect(canTransition(SessionState.DESCONECTADO, SessionState.REINICIANDO)).toBe(true);
  });

  it("bloqueia transição de PAUSADO direto para ERRO", () => {
    expect(canTransition(SessionState.PAUSADO, SessionState.ERRO)).toBe(false);
  });
});

___CLAUDE_EOF_MARKER___

mkdir -p "."
cat > "tsconfig.json" << '___CLAUDE_EOF_MARKER___'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "moduleResolution": "node",
    "lib": ["ES2022", "DOM"],
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": false,
    "sourceMap": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules", "dist", "tests"]
}

___CLAUDE_EOF_MARKER___

echo "Pronto! Todos os arquivos foram criados."
echo "Agora rode: git add . && git commit -m \"primeira versao\" && git push"
