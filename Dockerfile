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

# Build minimal serving image from AOT-compiled `/server`
# and the pre-built AOT-runtime in the `/runtime/` directory of the base image.
FROM scratch

# Environment defaults (override at runtime with -e).
ARG PORT=8080
ARG MONGO_URI
ARG PROXY_URL
ARG STREAM_MODE=redirect
ENV PORT=${PORT} \
    MONGO_URI=${MONGO_URI} \
    PROXY_URL=${PROXY_URL} \
    STREAM_MODE=${STREAM_MODE}

COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/
# Needed for Swagger UI in runtime.
COPY --from=build /app/openapi.yaml /app/openapi.yaml

# Start server.
EXPOSE 8080
CMD ["/app/bin/server"]
