# Video Preview Architecture

## Цель

Показывать видео с локального Windows-компьютера прямо внутри веб-чата ChatGPT через кастомный MCP app.

Текущая реализация использует обычный HTTPS media URL. Это оказалось надёжнее, чем передавать бинарное видео через MCP payload или пытаться использовать `blob:` URL внутри sandbox ChatGPT.

## Финальный flow

```text
ChatGPT
  |
  | preview_video(path)
  v
Desktop Commander patch
  |
  | POST /register
  v
localhost media-server
127.0.0.1:39127
  |
  | opaque token
  v
preview_video result
  |
  | hidden _meta.mediaUrl
  v
MCP Apps video-player
  |
  | HTTPS + HTTP Range
  v
Cloudflare Quick Tunnel
  |
  v
localhost media-server
  |
  v
original local MP4/WebM/Ogg file
```

## Почему не binary MCP payload

Передача видео как base64 внутри tool-result:

- раздувает MCP response примерно на треть;
- упирается в лимиты транспорта;
- плохо масштабируется на ролики десятков мегабайт;
- засоряет tool history и UI lifecycle.

## Почему не `resources/read`

Dynamic server resources тестировались, но ChatGPT Web отклонял их внутри MCP App widget с ошибкой:

```text
MCP app cannot read resource outside its widget scope
```

Даже после объявления resource templates и конкретных slots поведение host оставалось ограничивающим.

## Почему не `blob:`

После успешной доставки байтов в iframe ChatGPT Web отклонял:

```text
MEDIA_ERR_SRC_NOT_SUPPORTED
Media load rejected by URL safety check
```

То есть сам sandbox запрещал `blob:` как media source.

## Почему не `window.openai.uploadFile`

ChatGPT File API возвращал:

```text
Unsupported file type
```

для `video/mp4`, включая повтор из прямого пользовательского клика.

## Почему HTTPS media server

HTML5 video штатно работает с HTTPS URL и HTTP Range.

Это даёт:

- настоящий streaming;
- быструю перемотку;
- браузеру не нужно держать весь ролик в RAM;
- MCP result остаётся маленьким;
- video decoder получает обычный web-resource.

## Media server

Файл:

```text
media-server.mjs
```

Слушает:

```text
127.0.0.1:39127
```

Endpoints:

```text
GET  /health
POST /register
GET  /media/<token>
HEAD /media/<token>
```

`/register` требует header:

```text
x-rdc-media-secret
```

Secret генерируется заново при каждом запуске `rc-mcp`.

Файл нельзя получить по исходному filesystem path. После регистрации создаётся случайный opaque token.

## Range support

Media server поддерживает:

```http
Range: bytes=0-1023
Range: bytes=-65536
```

и отвечает:

```http
206 Partial Content
Accept-Ranges: bytes
Content-Range: ...
```

Это особенно важно для MP4, где `moov` atom может находиться в конце файла.

## Unicode filename

HTTP header не содержит сырое кириллическое имя.

Используется:

```http
Content-Disposition:
inline;
filename="ascii-fallback.mp4";
filename*=UTF-8''<percent-encoded-name>
```

Это исправляет HTTP 500 для файлов вроде `Гонка.mp4`.

## Cloudflare Quick Tunnel

Launcher поднимает:

```text
cloudflared tunnel --url http://127.0.0.1:39127
```

Hostname случайный при каждом запуске:

```text
https://<random>.trycloudflare.com
```

MCP App CSP использует wildcard:

```text
https://*.trycloudflare.com
```

поэтому пересоздавать app из-за нового media hostname не требуется.

## Widget

Активный resource URI:

```text
ui://desktop-commander/video-player-v9
```

Widget:

- ждёт `loadedmetadata`;
- показывает настоящую длительность;
- ловит `MediaError`;
- сообщает ошибку модели через update-model-context;
- поддерживает Retry;
- запрашивает Fullscreen/PiP через MCP Apps display modes.

## Lifecycle

`rc-mcp` запускает:

1. local media-server;
2. Cloudflare Quick Tunnel;
3. OpenAI Secure MCP Tunnel.

`Ctrl+C` завершает все процессы и удаляет `.runtime/media-session.json`.

## Ограничения

Default max video size:

```text
50 MB
```

Настройка:

```powershell
$env:RDC_VIDEO_PREVIEW_MAX_MB=100
rc-mcp
```

Media token TTL:

```text
30 minutes
```

Если `rc-mcp` остановлен, media URL перестаёт работать сразу независимо от TTL.
