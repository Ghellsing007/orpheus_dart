# Use Dart 3.9.x to match pubspec SDK constraint.
FROM dart:3.9 AS build

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY . .
# Ensure OpenAPI spec is included for Swagger UI.
COPY openapi.yaml /app/openapi.yaml
RUN dart compile exe bin/server.dart -o bin/server

# Imagen de runtime basada en Dart con ffmpeg + yt-dlp instalados.
FROM dart:3.9 AS runtime

# Environment defaults (override at runtime with -e).
ARG PORT=8080
ARG MONGO_URI
ARG PROXY_URL
ARG STREAM_MODE=redirect
ARG USE_YTDLP=true
ARG DOWNLOAD_TIMEOUT_SEC=240
ARG DOWNLOAD_MAX_CONCURRENT=3
ENV PORT=${PORT} \
    MONGO_URI=${MONGO_URI} \
    PROXY_URL=${PROXY_URL} \
    STREAM_MODE=${STREAM_MODE} \
    USE_YTDLP=${USE_YTDLP} \
    DOWNLOAD_TIMEOUT_SEC=${DOWNLOAD_TIMEOUT_SEC} \
    DOWNLOAD_MAX_CONCURRENT=${DOWNLOAD_MAX_CONCURRENT}

# Dependencias mínimas + ffmpeg + yt-dlp para descargas MP3
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg curl python3 \
    && curl -L "https://github.com/yt-dlp/yt-dlp/releases/download/2024.11.18/yt-dlp" -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/bin/server /app/bin/
# Needed for Swagger UI in runtime.
COPY --from=build /app/openapi.yaml /app/openapi.yaml

# Start server.
EXPOSE 8080
CMD ["/app/bin/server"]
