# Documentación Completa del API Orpheus Dart para Frontend Web

## 📋 Descripción General

**Orpheus Dart** es un servidor backend desarrollado en Dart usando el framework Shelf que replica la funcionalidad de Musify. Proporciona una API REST completa para búsqueda de música, streaming, gestión de playlists, letras, recomendaciones y estado de usuario.

### Características Principales

- ✅ Búsqueda de canciones y sugerencias de búsqueda
- ✅ Streaming de audio desde YouTube con múltiples modos
- ✅ Gestión de playlists (curadas, personalizadas, de YouTube)
- ✅ Sistema de usuarios con likes, recientes y playlists personalizadas
- ✅ Letras de canciones
- ✅ Recomendaciones personalizadas
- ✅ Integración con SponsorBlock para saltar segmentos
- ✅ CORS habilitado para consumo desde frontend web
- ✅ Documentación OpenAPI/Swagger UI disponible

---

## 🌐 Configuración del Servidor

### Variables de Entorno

El servidor requiere las siguientes variables de entorno:

```env
PORT=8080                                    # Puerto del servidor (default: 8080)
MONGO_URI=mongodb://...                      # URI de conexión a MongoDB (requerido)
PROXY_URL=host:port                          # Proxy opcional para YouTube
STREAM_MODE=redirect                         # redirect | proxy | url
```

### URL Base

Por defecto, el servidor corre en `http://localhost:8080`. Ajusta según tu configuración.

### Documentación Interactiva

Accede a la documentación Swagger UI en: `http://localhost:8080/docs/`

---

## 🔌 Endpoints Disponibles

### 1. Health Check

**Verificar estado del servidor**

```http
GET /health
```

**Respuesta:**

```json
{
  "status": "ok"
}
```

**Ejemplo en JavaScript:**

```javascript
const response = await fetch("http://localhost:8080/health");
const data = await response.json();
console.log(data.status); // "ok"
```

---

### 2. Búsqueda de Canciones

**Buscar canciones por término**

```http
GET /search?q={query}
```

**Parámetros:**

- `q` (requerido): Término de búsqueda

**Respuesta:**

```json
{
  "items": [
    {
      "id": 0,
      "ytid": "dQw4w9WgXcQ",
      "title": "Never Gonna Give You Up",
      "artist": "Rick Astley",
      "image": "https://i.ytimg.com/vi/.../default.jpg",
      "lowResImage": "https://i.ytimg.com/vi/.../mqdefault.jpg",
      "highResImage": "https://i.ytimg.com/vi/.../maxresdefault.jpg",
      "duration": 213,
      "isLive": false
    }
  ]
}
```

**Estructura de Canción:**

- `id`: Índice numérico (generalmente 0)
- `ytid`: ID de YouTube de la canción
- `title`: Título formateado (sin "Official Video", etc.)
- `artist`: Artista extraído del título
- `image`: URL de imagen estándar
- `lowResImage`: URL de imagen baja resolución
- `highResImage`: URL de imagen alta resolución
- `duration`: Duración en segundos
- `isLive`: Boolean indicando si es transmisión en vivo

**Ejemplo en JavaScript:**

```javascript
async function searchSongs(query) {
  const response = await fetch(
    `http://localhost:8080/search?q=${encodeURIComponent(query)}`
  );
  const data = await response.json();
  return data.items;
}

// Uso
const songs = await searchSongs("rick astley");
console.log(songs);
```

---

### 3. Sugerencias de Búsqueda

**Obtener sugerencias de autocompletado**

```http
GET /suggestions?q={query}
```

**Parámetros:**

- `q` (requerido): Término de búsqueda parcial

**Respuesta:**

```json
{
  "items": [
    "rick astley",
    "rick astley never gonna give you up",
    "rick astley songs"
  ]
}
```

**Ejemplo en JavaScript:**

```javascript
async function getSuggestions(query) {
  const response = await fetch(
    `http://localhost:8080/suggestions?q=${encodeURIComponent(query)}`
  );
  const data = await response.json();
  return data.items;
}

// Uso en input de búsqueda
const input = document.getElementById("search-input");
input.addEventListener("input", async (e) => {
  const suggestions = await getSuggestions(e.target.value);
  // Mostrar sugerencias en UI
});
```

---

### 4. Listar Playlists

**Obtener playlists curadas y/o en línea**

```http
GET /playlists?query={query}&type={type}&online={online}
```

**Parámetros:**

- `query` (opcional): Filtrar por título
- `type` (opcional): `all` | `album` | `playlist` (default: `all`)
- `online` (opcional): `true` | `false` - Incluir búsqueda en línea (default: `false`)

**Respuesta:**

```json
{
  "items": [
    {
      "ytid": "PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx",
      "title": "Top 50 Global",
      "image": "https://charts-images.scdn.co/...",
      "list": [],
      "isAlbum": false
    }
  ]
}
```

**Estructura de Playlist:**

- `ytid`: ID de YouTube de la playlist
- `title`: Título de la playlist
- `image`: URL de la imagen de portada
- `list`: Array de canciones (vacío hasta que se obtenga el detalle)
- `isAlbum`: Boolean (solo en playlists curadas)
- `source`: `"youtube"` | `"user-created"` (solo en playlists en línea o personalizadas)

**Ejemplo en JavaScript:**

```javascript
async function getPlaylists(query = "", type = "all", includeOnline = false) {
  const params = new URLSearchParams();
  if (query) params.append("query", query);
  if (type !== "all") params.append("type", type);
  if (includeOnline) params.append("online", "true");

  const response = await fetch(
    `http://localhost:8080/playlists?${params.toString()}`
  );
  const data = await response.json();
  return data.items;
}

// Obtener todas las playlists
const allPlaylists = await getPlaylists();

// Buscar playlists con búsqueda en línea
const searchResults = await getPlaylists("top", "all", true);
```

---

### 5. Detalle de Playlist

**Obtener información completa de una playlist con sus canciones**

```http
GET /playlists/{id}?userId={userId}
```

**Parámetros:**

- `id` (requerido en path): ID de YouTube de la playlist
- `userId` (opcional): ID del usuario (para playlists personalizadas)

**Respuesta:**

```json
{
  "ytid": "PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx",
  "title": "Top 50 Global",
  "image": "https://charts-images.scdn.co/...",
  "source": "youtube",
  "list": [
    {
      "id": 0,
      "ytid": "dQw4w9WgXcQ",
      "title": "Never Gonna Give You Up",
      "artist": "Rick Astley",
      "image": "...",
      "duration": 213,
      "isLive": false
    }
  ]
}
```

**Ejemplo en JavaScript:**

```javascript
async function getPlaylistDetails(playlistId, userId = null) {
  const url = userId
    ? `http://localhost:8080/playlists/${playlistId}?userId=${userId}`
    : `http://localhost:8080/playlists/${playlistId}`;

  const response = await fetch(url);
  const data = await response.json();
  return data;
}

// Obtener playlist
const playlist = await getPlaylistDetails("PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx");
console.log(playlist.list); // Array de canciones
```

---

### 6. Detalle de Canción

**Obtener información detallada de una canción**

```http
GET /songs/{id}
```

**Parámetros:**

- `id` (requerido en path): ID de YouTube de la canción

**Respuesta:**

```json
{
  "id": 0,
  "ytid": "dQw4w9WgXcQ",
  "title": "Never Gonna Give You Up",
  "artist": "Rick Astley",
  "image": "https://i.ytimg.com/vi/.../default.jpg",
  "lowResImage": "https://i.ytimg.com/vi/.../mqdefault.jpg",
  "highResImage": "https://i.ytimg.com/vi/.../maxresdefault.jpg",
  "duration": 213,
  "isLive": false
}
```

**Ejemplo en JavaScript:**

```javascript
async function getSongDetails(songId) {
  const response = await fetch(`http://localhost:8080/songs/${songId}`);
  const data = await response.json();
  return data;
}
```

---

### 7. Streaming de Audio

**Obtener URL de streaming o redirección**

```http
GET /songs/{id}/stream?quality={quality}&mode={mode}&proxy={proxy}
```

**Parámetros:**

- `id` (requerido en path): ID de YouTube de la canción
- `quality` (opcional): `low` | `medium` | `high` (default: `high`)
- `mode` (opcional): `redirect` | `proxy` | `url` (default: configurado en servidor)
- `proxy` (opcional): `true` | `false` - Usar proxy para obtener URL

**Modos de Streaming:**

1. **`redirect`** (302): Redirección directa a la URL de YouTube

   ```javascript
   // El navegador sigue automáticamente la redirección
   const audio = new Audio(
     `http://localhost:8080/songs/${songId}/stream?mode=redirect`
   );
   audio.play();
   ```

2. **`url`**: Devuelve JSON con la URL

   ```json
   {
     "url": "https://rr3---sn-...",
     "mode": "url"
   }
   ```

   ```javascript
   const response = await fetch(
     `http://localhost:8080/songs/${songId}/stream?mode=url`
   );
   const data = await response.json();
   const audio = new Audio(data.url);
   audio.play();
   ```

3. **`proxy`**: El servidor retransmite el audio (mayor carga en servidor)
   ```javascript
   // El servidor actúa como proxy, útil para evitar CORS
   const audio = new Audio(
     `http://localhost:8080/songs/${songId}/stream?mode=proxy`
   );
   audio.play();
   ```

**Ejemplo Completo:**

```javascript
async function getStreamUrl(songId, quality = "high", mode = "url") {
  const params = new URLSearchParams({
    quality,
    mode,
  });

  const response = await fetch(
    `http://localhost:8080/songs/${songId}/stream?${params.toString()}`
  );

  if (mode === "redirect") {
    // El navegador maneja la redirección automáticamente
    return response.url;
  }

  const data = await response.json();
  return data.url;
}

// Reproducir canción
async function playSong(songId) {
  const url = await getStreamUrl(songId, "high", "url");
  const audio = new Audio(url);
  audio.play();
}
```

---

### 8. Segmentos de SponsorBlock

**Obtener segmentos para saltar (sponsors, intros, etc.)**

```http
GET /songs/{id}/segments
```

**Parámetros:**

- `id` (requerido en path): ID de YouTube de la canción

**Respuesta:**

```json
{
  "items": [
    {
      "start": 10,
      "end": 30
    },
    {
      "start": 120,
      "end": 150
    }
  ]
}
```

**Ejemplo en JavaScript:**

```javascript
async function getSkipSegments(songId) {
  const response = await fetch(
    `http://localhost:8080/songs/${songId}/segments`
  );
  const data = await response.json();
  return data.items;
}

// Usar con reproductor de audio
const segments = await getSkipSegments(songId);
const audio = document.getElementById("audio-player");

audio.addEventListener("timeupdate", () => {
  const currentTime = audio.currentTime;
  const segment = segments.find(
    (s) => currentTime >= s.start && currentTime < s.end
  );
  if (segment) {
    audio.currentTime = segment.end; // Saltar segmento
  }
});
```

---

### 9. Letras de Canciones

**Obtener letras de una canción**

```http
GET /lyrics?artist={artist}&title={title}
```

**Parámetros:**

- `artist` (requerido): Nombre del artista
- `title` (requerido): Título de la canción

**Respuesta (encontrado):**

```json
{
  "lyrics": "Never gonna give you up\nNever gonna let you down...",
  "found": true
}
```

**Respuesta (no encontrado):**

```json
{
  "lyrics": null,
  "found": false
}
```

**Ejemplo en JavaScript:**

```javascript
async function getLyrics(artist, title) {
  const params = new URLSearchParams({
    artist: encodeURIComponent(artist),
    title: encodeURIComponent(title),
  });

  const response = await fetch(
    `http://localhost:8080/lyrics?${params.toString()}`
  );
  const data = await response.json();
  return data;
}

// Uso
const lyricsData = await getLyrics("Rick Astley", "Never Gonna Give You Up");
if (lyricsData.found) {
  console.log(lyricsData.lyrics);
}
```

---

### 10. Recomendaciones

**Obtener recomendaciones personalizadas o globales**

```http
GET /recommendations?userId={userId}
```

**Parámetros:**

- `userId` (opcional): ID del usuario (si se proporciona, devuelve recomendaciones personalizadas)

**Respuesta:**

```json
{
  "items": [
    {
      "id": 0,
      "ytid": "dQw4w9WgXcQ",
      "title": "Never Gonna Give You Up",
      "artist": "Rick Astley",
      "duration": 213,
      "isLive": false
    }
  ]
}
```

**Ejemplo en JavaScript:**

```javascript
async function getRecommendations(userId = null) {
  const url = userId
    ? `http://localhost:8080/recommendations?userId=${userId}`
    : "http://localhost:8080/recommendations";

  const response = await fetch(url);
  const data = await response.json();
  return data.items;
}

// Recomendaciones personalizadas
const userRecs = await getRecommendations("user123");

// Recomendaciones globales
const globalRecs = await getRecommendations();
```

---

## 👤 Gestión de Usuarios

### Estructura de Usuario

```json
{
  "_id": "user123",
  "likedSongs": [],
  "likedPlaylists": [],
  "recentlyPlayed": [],
  "customPlaylists": [],
  "playlistFolders": [],
  "youtubePlaylists": []
}
```

---

### 11. Obtener Estado del Usuario

**Obtener todo el estado del usuario**

```http
GET /users/{userId}/state
```

**Ejemplo en JavaScript:**

```javascript
async function getUserState(userId) {
  const response = await fetch(`http://localhost:8080/users/${userId}/state`);
  const data = await response.json();
  return data;
}

const user = await getUserState("user123");
console.log(user.likedSongs);
console.log(user.recentlyPlayed);
```

---

### 12. Like/Unlike Canción

**Agregar o quitar canción de favoritos**

```http
POST /users/{userId}/likes/song
Content-Type: application/json

{
  "songId": "dQw4w9WgXcQ",
  "add": true
}
```

**Body:**

- `songId` (requerido): ID de YouTube de la canción
- `add` (opcional): `true` para agregar, `false` para quitar (default: `true`)

**Respuesta:**

```json
{
  "likedSongs": [
    {
      "id": 0,
      "ytid": "dQw4w9WgXcQ",
      "title": "Never Gonna Give You Up",
      "artist": "Rick Astley",
      "duration": 213
    }
  ],
  "count": 1
}
```

**Ejemplo en JavaScript:**

```javascript
async function likeSong(userId, songId, add = true) {
  const response = await fetch(
    `http://localhost:8080/users/${userId}/likes/song`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        songId,
        add,
      }),
    }
  );
  const data = await response.json();
  return data;
}

// Agregar a favoritos
await likeSong("user123", "dQw4w9WgXcQ", true);

// Quitar de favoritos
await likeSong("user123", "dQw4w9WgXcQ", false);
```

---

### 13. Like/Unlike Playlist

**Agregar o quitar playlist de favoritos**

```http
POST /users/{userId}/likes/playlist
Content-Type: application/json

{
  "playlistId": "PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx",
  "add": true
}
```

**Ejemplo en JavaScript:**

```javascript
async function likePlaylist(userId, playlistId, add = true) {
  const response = await fetch(
    `http://localhost:8080/users/${userId}/likes/playlist`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        playlistId,
        add,
      }),
    }
  );
  const data = await response.json();
  return data;
}
```

---

### 14. Agregar a Recientes

**Registrar canción como recientemente reproducida**

```http
POST /users/{userId}/recently
Content-Type: application/json

{
  "songId": "dQw4w9WgXcQ"
}
```

**Ejemplo en JavaScript:**

```javascript
async function addRecentlyPlayed(userId, songId) {
  const response = await fetch(
    `http://localhost:8080/users/${userId}/recently`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        songId,
      }),
    }
  );
  const data = await response.json();
  return data.recentlyPlayed;
}

// Llamar cuando se reproduce una canción
await addRecentlyPlayed("user123", "dQw4w9WgXcQ");
```

---

### 15. Agregar Playlist de YouTube

**Agregar playlist de YouTube al usuario**

```http
POST /users/{userId}/playlists/youtube
Content-Type: application/json

{
  "playlistId": "PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx"
}
```

**Ejemplo en JavaScript:**

```javascript
async function addYouTubePlaylist(userId, playlistId) {
  const response = await fetch(
    `http://localhost:8080/users/${userId}/playlists/youtube`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        playlistId,
      }),
    }
  );
  const data = await response.json();
  return data.youtubePlaylists;
}
```

---

### 16. Crear Playlist Personalizada

**Crear una nueva playlist personalizada**

```http
POST /users/{userId}/playlists/custom
Content-Type: application/json

{
  "title": "Mi Playlist",
  "image": "https://example.com/image.jpg"
}
```

**Body:**

- `title` (requerido): Título de la playlist
- `image` (opcional): URL de la imagen de portada

**Respuesta:**

```json
{
  "customPlaylists": [
    {
      "ytid": "custom-uuid-v4",
      "title": "Mi Playlist",
      "image": "https://example.com/image.jpg",
      "source": "user-created",
      "list": [],
      "createdAt": 1234567890
    }
  ]
}
```

**Ejemplo en JavaScript:**

```javascript
async function createCustomPlaylist(userId, title, image = null) {
  const body = { title };
  if (image) body.image = image;

  const response = await fetch(
    `http://localhost:8080/users/${userId}/playlists/custom`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    }
  );
  const data = await response.json();
  return data.customPlaylists;
}

// Crear playlist
const playlists = await createCustomPlaylist("user123", "Mis Favoritas");
const newPlaylistId = playlists[playlists.length - 1].ytid;
```

---

### 17. Agregar Canción a Playlist Personalizada

**Agregar canción a una playlist personalizada**

```http
POST /users/{userId}/playlists/custom/{playlistId}/songs
Content-Type: application/json

{
  "songId": "dQw4w9WgXcQ"
}
```

**Ejemplo en JavaScript:**

```javascript
async function addSongToCustomPlaylist(userId, playlistId, songId) {
  const response = await fetch(
    `http://localhost:8080/users/${userId}/playlists/custom/${playlistId}/songs`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        songId,
      }),
    }
  );
  const data = await response.json();
  return data.customPlaylists;
}
```

---

## 🎨 Ejemplo de Integración Completa

### Cliente API en JavaScript

```javascript
class OrpheusAPI {
  constructor(baseURL = "http://localhost:8080") {
    this.baseURL = baseURL;
  }

  async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;
    const response = await fetch(url, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...options.headers,
      },
    });

    if (!response.ok) {
      const error = await response
        .json()
        .catch(() => ({ error: "Unknown error" }));
      throw new Error(error.error || `HTTP ${response.status}`);
    }

    return response.json();
  }

  // Búsqueda
  async searchSongs(query) {
    const data = await this.request(`/search?q=${encodeURIComponent(query)}`);
    return data.items;
  }

  async getSuggestions(query) {
    const data = await this.request(
      `/suggestions?q=${encodeURIComponent(query)}`
    );
    return data.items;
  }

  // Playlists
  async getPlaylists(query = "", type = "all", online = false) {
    const params = new URLSearchParams();
    if (query) params.append("query", query);
    if (type !== "all") params.append("type", type);
    if (online) params.append("online", "true");
    const data = await this.request(`/playlists?${params}`);
    return data.items;
  }

  async getPlaylistDetails(playlistId, userId = null) {
    const url = userId
      ? `/playlists/${playlistId}?userId=${userId}`
      : `/playlists/${playlistId}`;
    return this.request(url);
  }

  // Canciones
  async getSongDetails(songId) {
    return this.request(`/songs/${songId}`);
  }

  async getStreamUrl(songId, quality = "high", mode = "url") {
    const params = new URLSearchParams({ quality, mode });
    return this.request(`/songs/${songId}/stream?${params}`);
  }

  async getSkipSegments(songId) {
    const data = await this.request(`/songs/${songId}/segments`);
    return data.items;
  }

  // Letras
  async getLyrics(artist, title) {
    const params = new URLSearchParams({
      artist: encodeURIComponent(artist),
      title: encodeURIComponent(title),
    });
    return this.request(`/lyrics?${params}`);
  }

  // Recomendaciones
  async getRecommendations(userId = null) {
    const url = userId
      ? `/recommendations?userId=${userId}`
      : "/recommendations";
    const data = await this.request(url);
    return data.items;
  }

  // Usuario
  async getUserState(userId) {
    return this.request(`/users/${userId}/state`);
  }

  async likeSong(userId, songId, add = true) {
    return this.request(`/users/${userId}/likes/song`, {
      method: "POST",
      body: JSON.stringify({ songId, add }),
    });
  }

  async likePlaylist(userId, playlistId, add = true) {
    return this.request(`/users/${userId}/likes/playlist`, {
      method: "POST",
      body: JSON.stringify({ playlistId, add }),
    });
  }

  async addRecentlyPlayed(userId, songId) {
    return this.request(`/users/${userId}/recently`, {
      method: "POST",
      body: JSON.stringify({ songId }),
    });
  }

  async addYouTubePlaylist(userId, playlistId) {
    return this.request(`/users/${userId}/playlists/youtube`, {
      method: "POST",
      body: JSON.stringify({ playlistId }),
    });
  }

  async createCustomPlaylist(userId, title, image = null) {
    const body = { title };
    if (image) body.image = image;
    return this.request(`/users/${userId}/playlists/custom`, {
      method: "POST",
      body: JSON.stringify(body),
    });
  }

  async addSongToCustomPlaylist(userId, playlistId, songId) {
    return this.request(
      `/users/${userId}/playlists/custom/${playlistId}/songs`,
      {
        method: "POST",
        body: JSON.stringify({ songId }),
      }
    );
  }
}

// Uso
const api = new OrpheusAPI("http://localhost:8080");

// Buscar canciones
const songs = await api.searchSongs("rick astley");

// Obtener playlist
const playlist = await api.getPlaylistDetails(
  "PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx"
);

// Reproducir canción
async function playSong(songId) {
  const streamData = await api.getStreamUrl(songId, "high", "url");
  const audio = new Audio(streamData.url);
  audio.play();

  // Registrar como reciente
  await api.addRecentlyPlayed("user123", songId);
}

// Gestión de favoritos
await api.likeSong("user123", songId, true);
```

---

## 🎵 Ejemplo de Reproductor de Audio

```javascript
class AudioPlayer {
  constructor(api, userId) {
    this.api = api;
    this.userId = userId;
    this.audio = new Audio();
    this.currentSong = null;
    this.skipSegments = [];

    this.audio.addEventListener("timeupdate", () => this.handleTimeUpdate());
    this.audio.addEventListener("ended", () => this.handleSongEnded());
  }

  async loadSong(songId) {
    try {
      // Obtener detalles de la canción
      this.currentSong = await this.api.getSongDetails(songId);

      // Obtener segmentos de SponsorBlock
      this.skipSegments = await this.api.getSkipSegments(songId);

      // Obtener URL de streaming
      const streamData = await this.api.getStreamUrl(songId, "high", "url");

      // Cargar y reproducir
      this.audio.src = streamData.url;
      await this.audio.play();

      // Registrar como reciente
      await this.api.addRecentlyPlayed(this.userId, songId);

      return this.currentSong;
    } catch (error) {
      console.error("Error loading song:", error);
      throw error;
    }
  }

  handleTimeUpdate() {
    const currentTime = this.audio.currentTime;

    // Saltar segmentos de SponsorBlock
    const segment = this.skipSegments.find(
      (s) => currentTime >= s.start && currentTime < s.end
    );
    if (segment) {
      this.audio.currentTime = segment.end;
    }
  }

  handleSongEnded() {
    // Lógica para siguiente canción
    console.log("Song ended");
  }

  play() {
    return this.audio.play();
  }

  pause() {
    this.audio.pause();
  }

  setVolume(volume) {
    this.audio.volume = volume;
  }
}

// Uso
const api = new OrpheusAPI();
const player = new AudioPlayer(api, "user123");

// Reproducir canción
await player.loadSong("dQw4w9WgXcQ");
```

---

## ⚠️ Manejo de Errores

Todos los endpoints pueden devolver errores. Formato típico:

```json
{
  "error": "Mensaje de error descriptivo"
}
```

**Códigos de estado comunes:**

- `200`: Éxito
- `400`: Error de validación (parámetros faltantes o inválidos)
- `404`: Recurso no encontrado
- `502`: Error del servidor (ej: proxy falló)

**Ejemplo de manejo:**

```javascript
try {
  const songs = await api.searchSongs("query");
} catch (error) {
  if (error.message.includes("400")) {
    console.error("Parámetros inválidos");
  } else if (error.message.includes("404")) {
    console.error("No encontrado");
  } else {
    console.error("Error desconocido:", error);
  }
}
```

---

## 🔒 CORS y Seguridad

El servidor tiene CORS habilitado por defecto, permitiendo peticiones desde cualquier origen. Para producción, considera:

1. Configurar CORS específico en el servidor
2. Implementar autenticación si es necesario
3. Validar y sanitizar inputs en el frontend
4. Manejar errores de red apropiadamente

---

## 📝 Notas Importantes

1. **Caché**: El servidor implementa caché para búsquedas, playlists y URLs de streaming. Las URLs de streaming se validan antes de devolverlas.

2. **IDs de Usuario**: El sistema no tiene autenticación integrada. Debes generar y gestionar los IDs de usuario en tu frontend (ej: UUID, hash, etc.).

3. **Streaming en Vivo**: Las transmisiones en vivo (`isLive: true`) usan un método diferente para obtener la URL.

4. **Calidad de Audio**: Las calidades disponibles dependen de lo que YouTube proporcione. El servidor selecciona la mejor calidad disponible según el parámetro.

5. **Modo Proxy**: El modo `proxy` retransmite el audio a través del servidor, lo que aumenta la carga. Úsalo solo si es necesario (ej: problemas de CORS).

---

## 🚀 Próximos Pasos

1. **Integrar el cliente API** en tu aplicación frontend
2. **Implementar autenticación** si necesitas usuarios reales
3. **Agregar manejo de errores** robusto
4. **Implementar caché en el frontend** para mejorar rendimiento
5. **Agregar tests** para tu integración

---

## 📚 Recursos Adicionales

- **Documentación Swagger**: `http://localhost:8080/docs/`
- **OpenAPI Spec**: Ver `openapi.yaml` en el repositorio
- **Código fuente**: Revisar `lib/routes/api_router.dart` para detalles de implementación

---

¡Listo para construir tu aplicación de música! 🎵
