FROM node:20-alpine
WORKDIR /app

# Copy server package definitions and install production dependencies
COPY server/package*.json ./server/
RUN cd server && npm install --omit=dev

# Copy server code and assets
COPY server/ ./server/
COPY assets/ ./assets/

ENV PORT=10000
ENV NODE_ENV=production

EXPOSE 10000

CMD ["node", "server/index.js"]
