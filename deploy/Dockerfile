FROM node:24.21.0-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY bridge ./bridge
COPY vendor ./vendor
COPY scripts/cloud-config.mjs scripts/start-cloud.mjs ./scripts/
COPY build/web-online ./build/web-online
ENV NODE_ENV=production TK_HOST=0.0.0.0 TK_DATA_DIR=/tmp/three-kingdoms
USER node
EXPOSE 3080
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3080)+'/readyz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
CMD ["node", "scripts/start-cloud.mjs"]
