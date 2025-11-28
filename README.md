Backend Dart (Shelf) que replica la lógica clave de Musify móvil: búsqueda y streaming con `youtube_explode_dart`, playlists curadas, sugerencias, recomendaciones, letras, SponsorBlock y estado de usuario en Mongo.

## Requisitos
- Dart SDK 3.9+
- MongoDB (`MONGO_URI` ya provisto en `.env`)

## Configuración
1. Copia `.env.example` a `.env` y ajusta:
   ```
   PORT=8080
   MONGO_URI=mongodb+srv://root:root@cluster0.pfs0rzo.mongodb.net/orpheus-backend-v1?retryWrites=true&w=majority&appName=Cluster0
   PROXY_URL=         # opcional, host:port para usar proxy
   STREAM_MODE=redirect   # redirect | proxy | url
   ```
2. Instala dependencias:
   ```
   dart pub get
   ```
3. Levanta el servidor:
   ```
   dart run bin/server.dart
   ```

## Endpoints principales
- `GET /health`
- `GET /search?q=` → canciones formateadas como la app.
- `GET /suggestions?q=`
- `GET /playlists?type=all|album|playlist&query=&online=true`
- `GET /playlists/{id}` → metadatos + canciones.
- `GET /songs/{id}` → detalles.
- `GET /songs/{id}/stream?quality=high&mode=redirect|proxy|url&proxy=true` → URL o redirección; `proxy` intenta retransmitir.
- `GET /songs/{id}/segments` → SponsorBlock.
- `GET /lyrics?artist=&title=`
- `GET /recommendations?userId=` → mezcla liked/recent + playlist global; si no hay userId usa playlist global.
- Estado de usuario:
  - `GET /users/{userId}/state`
  - `POST /users/{userId}/likes/song` `{songId, add}`
  - `POST /users/{userId}/likes/playlist` `{playlistId, add}`
  - `POST /users/{userId}/recently` `{songId}`
  - `POST /users/{userId}/playlists/youtube` `{playlistId}`
  - `POST /users/{userId}/playlists/custom` `{title, image?}`
- `POST /users/{userId}/playlists/custom/{playlistId}/songs` `{songId}`

## Docs (OpenAPI + Swagger UI)
- Esquema: `openapi.yaml` en la raíz.
- UI: `http://localhost:8080/docs/`

## Notas de streaming
- Modo `redirect` devuelve 302 a la URL de audio de YouTube (ligero).
- Modo `proxy` intenta retransmitir desde el backend (más costo).
- Las URLs se cachean por calidad y por modo (directo/proxy) para evitar caducidad.
