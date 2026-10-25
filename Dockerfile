FROM node:18-alpine AS build
WORKDIR /app
RUN npm install -g flutter-cli || true
# Alternatively, build locally and copy prebuilt web output
COPY build/web /app/build/web

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
