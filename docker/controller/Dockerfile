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

