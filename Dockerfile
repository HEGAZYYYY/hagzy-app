FROM node:20-alpine
WORKDIR /app

# Copy server package definitions and install production dependencies
COPY server/package*.json ./server/
RUN cd server && npm install --omit=dev

# Copy server code
COPY server/ ./server/

# Copy prebuilt Flutter web bundles and assets
COPY build/web/ ./build/web/
COPY build/web-admin/ ./build/web-admin/
COPY assets/ ./assets/

ENV PORT=10000
ENV NODE_ENV=production

EXPOSE 10000

CMD ["node", "server/index.js"]
