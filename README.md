# ChatGPT RDC Tunnel

Локальный Desktop Commander для веб-версии ChatGPT через OpenAI Secure MCP Tunnel.

Проект позволяет подключить ChatGPT к Windows-компьютеру без постоянного публичного MCP-сервера. Пока запущена команда `rc-mcp`, ChatGPT получает инструменты Desktop Commander для файловой системы, процессов, shell-команд и других локальных операций.

Дополнительно проект добавляет интерактивный видеоплеер MCP Apps: финальные локальные видео можно показывать прямо внутри чата ChatGPT.

## Архитектура

```text
ChatGPT Web
   |
   | OpenAI Secure MCP Tunnel
   v
tunnel-client
   |
   | stdio
   v
Desktop Commander MCP
   |
   +--> filesystem / shell / processes / git / ...
   |
   +--> preview_video
           |
           v
      local media-server
      127.0.0.1:39127
           |
           | Cloudflare Quick Tunnel
           v
      temporary HTTPS media URL
           |
           v
      MCP Apps <video> widget
      inside ChatGPT
```

Основной MCP-транспорт идёт только через OpenAI Secure MCP Tunnel.

Cloudflare Quick Tunnel используется отдельно и только для временной отдачи видео браузерному плееру. Он запускается вместе с `rc-mcp` и завершается по `Ctrl+C`.

## Что умеет

Базовые возможности приходят из Desktop Commander:

- чтение, поиск и редактирование файлов;
- создание и перемещение файлов и папок;
- запуск PowerShell и других локальных процессов;
- чтение вывода длительных процессов;
- Git/npm/Node/Python и другие CLI;
- пакетные операции, чтобы уменьшать число MCP-вызовов;
- человекопонятные progress labels в ChatGPT.

Дополнение этого проекта:

- `preview_video` для локальных MP4/WebM/Ogg;
- автоматический показ финального видео после генерации/рендера;
- inline-плеер внутри ChatGPT;
- Fullscreen и PiP, если их поддерживает ChatGPT host;
- Retry при ошибке воспроизведения;
- HTTP Range/206 для нормальной перемотки;
- Unicode-имена файлов, включая кириллицу;
- временные tokenized media URLs с TTL 30 минут.

## Требования

- Windows 10/11;
- Node.js 20+;
- npm;
- ChatGPT с поддержкой developer-mode MCP apps;
- OpenAI Platform organization с Secure MCP Tunnel;
- Runtime API key с необходимыми правами на Tunnels.

Проверенная конфигурация:

- Desktop Commander 0.2.52;
- OpenAI tunnel-client 0.0.15;
- @modelcontextprotocol/ext-apps 2.0.3.

## Установка

Клонируй репозиторий и открой PowerShell в его каталоге:

```powershell
git clone https://github.com/mixxator48/chatgpt-rdc-tunnel.git
cd chatgpt-rdc-tunnel
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\setup.ps1
```

`setup.ps1`:

1. выполняет `npm install`;
2. проверяет Desktop Commander 0.2.52;
3. накатывает локальный patch с UX и video-preview;
4. скачивает официальный OpenAI tunnel-client;
5. проверяет SHA-256 архива;
6. просит `tunnel_id`;
7. просит Runtime API key через SecureString;
8. сохраняет ключ в `.secrets\control-plane.key`;
9. создаёт профиль Secure MCP Tunnel;
10. запускает `tunnel-client doctor`;
11. добавляет команду `rc-mcp` в PowerShell profile.

После установки открой новое окно PowerShell.

## Запуск

```powershell
rc-mcp
```

Успешный запуск выглядит примерно так:

```text
Starting RDC media server...
Starting temporary HTTPS media tunnel...
Starting RC-MCP (Desktop Commander via stdio)...

RC-MCP ONLINE
ChatGPT connector: rdc-local
Media tunnel: https://example.trycloudflare.com
Press Ctrl+C or close this console to stop.
```

Остановка:

```text
Ctrl+C
```

После остановки завершаются:

- OpenAI tunnel-client;
- Cloudflare media tunnel;
- локальный media-server.

Проект не устанавливает Windows Service и не работает постоянно в фоне.

## Создание MCP app в ChatGPT

Пока `rc-mcp` запущен:

1. открой настройки ChatGPT;
2. создай новый developer-mode MCP app/plugin;
3. выбери **Tunnel**;
4. укажи существующий `tunnel_id`;
5. MCP authentication: **No authentication / Без аутентификации**;
6. дай приложению имя, например `RDC Local`;
7. создай приложение.

После изменения tool schema или UI resource URI рекомендуется создать свежий MCP app, чтобы ChatGPT заново выполнил discovery и не использовал старый кэш.

## Видеоплеер

Когда пользователь просит создать, сгенерировать, отрендерить, конвертировать или показать видео, модель может вызвать:

```text
preview_video(path)
```

Tool:

1. проверяет путь, формат и размер файла;
2. регистрирует файл в локальном media-server;
3. создаёт временный token;
4. возвращает ChatGPT только metadata;
5. передаёт URL видеоплееру через скрытый tool-result metadata.

Сам URL имеет вид:

```text
https://<random>.trycloudflare.com/media/<opaque-token>
```

Media server:

- слушает только `127.0.0.1:39127`;
- не умеет листинг файлов;
- регистрация требует случайный secret текущего запуска;
- отдаёт только заранее зарегистрированные tokenized URLs;
- поддерживает `HEAD`, `GET`, `Range` и `206 Partial Content`;
- TTL ссылки: 30 минут;
- корректно формирует `Content-Disposition` для Unicode-имён.

Поддерживаемые форматы:

- MP4;
- WebM;
- Ogg/OGV.

Лимит inline preview по умолчанию: 50 MB.

Его можно изменить перед запуском:

```powershell
$env:RDC_VIDEO_PREVIEW_MAX_MB=100
rc-mcp
```

Для подробностей см. [docs/VIDEO_PREVIEW.md](docs/VIDEO_PREVIEW.md).

## Безопасность

Это локальный инструмент с широкими возможностями. MCP может выполнять действия на компьютере в пределах прав текущего пользователя.

Рекомендации:

- запускай `rc-mcp` только когда нужен удалённый доступ из ChatGPT;
- останавливай через `Ctrl+C` после работы;
- не публикуй Runtime API key;
- не коммить `.secrets`, `profiles`, `.runtime`, `logs`;
- ограничивай `allowedDirectories` Desktop Commander, если нужен более узкий доступ;
- не делись своим tunnel_id и MCP app с чужим workspace;
- регулярно обновляй Desktop Commander и tunnel-client после проверки совместимости patch.

Временный media URL является bearer-ссылкой: любой, кто знает полный URL до истечения TTL, теоретически сможет скачать файл. URL содержит случайный token и существует только пока работают media-server и Cloudflare tunnel.

## Что хранится только локально

Git игнорирует:

```text
node_modules/
.runtime/
.secrets/
profiles/
logs/
*.log
*.zip
```

В репозитории нет Runtime API key, tunnel profile или текущего media-session secret.

## Пересборка video widget

Обычному пользователю это не требуется: готовый bundle уже лежит в patch.

Для разработки:

```powershell
npm install
npm run build:video-ui
```

После пересборки нужно обновить файл patch и проверить синтаксис.

## Troubleshooting

### `rc-mcp` не найден

Открой новое окно PowerShell после `setup.ps1` или выполни:

```powershell
. $PROFILE
```

### Порт 8788 занят

Вероятно, уже запущен другой tunnel-client. Заверши старый `rc-mcp`.

### Порт 39127 занят

Launcher автоматически завершит только осиротевший экземпляр **своего** `media-server.mjs`.

Если порт занят другим процессом, launcher ничего не убивает и покажет PID.

### Видео показывает Format error

Проверь, что используется актуальная версия patch. Текущая версия корректно обрабатывает Unicode-имена файлов и HTTP Range.

### Видео не открывается после изменения UI

Создай свежий MCP app в ChatGPT. Resource URI версионируется именно для обхода host cache.

### Проверка Secure MCP Tunnel

```powershell
.\.runtime\tunnel-client\tunnel-client.exe doctor --profile rdc-local --profile-dir .\profiles --explain
Invoke-WebRequest http://127.0.0.1:8788/readyz -UseBasicParsing
```

## Структура

```text
chatgpt-rdc-tunnel/
├─ README.md
├─ setup.ps1
├─ Start-RCMCP.ps1
├─ media-server.mjs
├─ package.json
├─ package-lock.json
├─ docs/
│  └─ VIDEO_PREVIEW.md
└─ patches/
   └─ desktop-commander-0.2.52/
      ├─ server.js
      ├─ tools/
      ├─ utils/
      └─ ui/
```

## Используемые проекты

- Desktop Commander: https://github.com/wonderwhy-er/DesktopCommanderMCP
- OpenAI Secure MCP Tunnel: https://github.com/openai/tunnel-client
- MCP Apps: https://github.com/modelcontextprotocol/ext-apps

## License

Desktop Commander patch derived files retain the upstream license in:

```text
patches/desktop-commander-0.2.52/LICENSE.upstream
```
