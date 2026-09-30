# ChatGPT + Desktop Commander через OpenAI Secure MCP Tunnel

Этот проект подключает локальный **Desktop Commander MCP** на Windows к ChatGPT через **OpenAI Secure MCP Tunnel**.

Никакой собственный MCP-сервер, публичный IP, VPS, Cloudflare Tunnel или проброс портов не нужен.

## Архитектура

```text
ChatGPT
   |
   | OpenAI Secure MCP Tunnel
   v
OpenAI tunnel endpoint
   ^
   | outbound HTTPS
   |
tunnel-client.exe
   |
   | stdio
   v
Desktop Commander MCP
   |
   v
Windows / файлы / PowerShell / процессы / Git / Node / Python
```

Ключевая особенность: Desktop Commander работает только пока пользователь вручную держит запущенной команду `rc-mcp`.
## Что устанавливается

- Desktop Commander MCP `0.2.52`
- OpenAI `tunnel-client` `0.0.15`
- локальный профиль туннеля
- локальный Runtime API key
- PowerShell-команда `rc-mcp`
- локальный UX-patch для Desktop Commander `0.2.52`:
  - отключает встроенные MCP UI previews;
  - добавляет batching-подсказки для чтения, записи и shell-команд;
  - добавляет динамические progress-метки вида `start_process · Проверяю тесты`;
  - показывает имя конкретного MCP tool без возврата тяжёлых preview-блоков.

Patched-файлы основаны на Desktop Commander 0.2.52 и распространяются вместе с upstream MIT license в `patches/desktop-commander-0.2.52/`.

Секреты и runtime-файлы не попадают в Git.

## Требования

- Windows 10/11
- PowerShell
- Node.js 18+ и npm
- аккаунт ChatGPT с возможностью создавать developer-mode MCP app/plugin
- OpenAI Platform organization
- права на Secure MCP Tunnel

Для создания/изменения туннеля нужны **Tunnels Read + Manage**.
Для запуска `tunnel-client` и выбора туннеля в ChatGPT нужны **Tunnels Read + Use**.

Официальная документация:
- https://developers.openai.com/api/docs/guides/secure-mcp-tunnels
- https://developers.openai.com/plugins/deploy/connect-chatgpt
## 1. Клонирование

Репозиторий приватный. Владелец должен добавить другого человека в Collaborators или позже сделать репозиторий публичным.

```powershell
git clone https://github.com/mixxator48/chatgpt-rdc-tunnel.git
cd chatgpt-rdc-tunnel
```

## 2. Создание своего OpenAI Secure MCP Tunnel

Откройте:

https://platform.openai.com/settings/organization/tunnels

Создайте новый tunnel endpoint и сохраните его `tunnel_id`.

**Важно:** в настройках этого tunnel добавьте association не только с вашей OpenAI Platform Organization, но и с **тем ChatGPT workspace**, в котором будете создавать MCP app/plugin. Без этой association ChatGPT может принять `tunnel_id`, но не сможет нормально создать или обнаружить MCP-приложение.

У пользователя также должны быть права **Tunnels Read + Use** для запуска tunnel-client и подключения tunnel в ChatGPT.

Он выглядит примерно так:

```text
tunnel_0123456789abcdef...
```

Важно: используйте **свой** tunnel_id. Никаких общих tunnel_id между разными людьми и ПК здесь не предполагается.

## 3. Создание Runtime API key

Откройте:

https://platform.openai.com/settings/organization/api-keys
Создайте отдельный Runtime API key, например с именем:

```text
chatgpt-rdc-tunnel
```

Не публикуйте ключ, не отправляйте его в чат и не коммитьте в Git.

## 4. Установка и настройка

Запустите:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Get-ChildItem -Recurse | Unblock-File
.\setup.ps1
```

Если проект был скачан ZIP-архивом через браузер, Windows может пометить `.ps1` как файл из интернета. В этом случае `RemoteSigned` всё равно потребует цифровую подпись. Команда `Get-ChildItem -Recurse | Unblock-File` снимает эту метку. При клонировании через `git clone` такая проблема обычно не возникает.

Скрипт:
1. проверит Node.js и npm;
2. установит Desktop Commander локально в проект;
3. скачает проверенную версию OpenAI tunnel-client;
4. проверит SHA256 архива;
5. попросит ваш `tunnel_id`;
6. попросит Runtime API key через скрытый ввод;
7. сохранит ключ только локально в `.secrets\control-plane.key`;
8. создаст профиль туннеля;
9. запустит `tunnel-client doctor`;
10. добавит команду `rc-mcp` в PowerShell profile.
После установки откройте **новое окно PowerShell**.

## 5. Ручной запуск

Включить доступ:

```powershell
rc-mcp
```

Пока это окно PowerShell открыто, ChatGPT может обращаться к Desktop Commander через ваш туннель.

Остановить доступ:

```text
Ctrl+C
```

После остановки `tunnel-client` больше не опрашивает OpenAI, а Desktop Commander завершается вместе с ним.

Никакая Windows Service, Task Scheduler или автозагрузка этим проектом не создаётся.

## 6. Создание MCP app/plugin в ChatGPT

В ChatGPT откройте раздел **Plugins** и создайте новый developer-mode MCP app.

При создании подключения:
- Connection: **Tunnel**
- выберите свой туннель из списка или вставьте свой `tunnel_id`
- MCP authentication: **No authentication / Без аутентификации**
- задайте удобное имя, например `RDC Local`
Перед созданием/проверкой плагина сначала запустите:

```powershell
rc-mcp
```

ChatGPT должен обнаружить инструменты Desktop Commander через тот же tunnel_id.

После создания добавьте плагин в чат и проверьте, например:

```text
Покажи конфигурацию Desktop Commander.
```

или:

```text
Покажи содержимое моей папки Downloads.
```

## Что умеет Desktop Commander

Через MCP доступны, среди прочего:

- чтение, запись, перемещение и поиск файлов;
- точечное редактирование файлов;
- PowerShell и другие локальные shell-команды;
- запуск и управление процессами;
- Git, npm, Node.js, Python и другие установленные CLI;
- работа с PDF, DOCX и Excel через инструменты Desktop Commander.
## Безопасность

Это полноценный инструмент удалённого доступа к локальной машине через MCP.

По умолчанию Desktop Commander может иметь широкий файловый доступ. В частности, значение:

```text
allowedDirectories: []
```

означает доступ ко всей файловой системе, а не запрет доступа.

Desktop Commander также имеет встроенный список `blockedCommands`, но это не полноценная песочница.

Рекомендации:
- запускайте `rc-mcp` только когда реально нужен доступ;
- завершайте работу через `Ctrl+C`;
- не делитесь Runtime API key;
- не используйте чужой tunnel_id;
- при необходимости ограничьте `allowedDirectories` рабочими папками;
- не подключайте этот tunnel к чужим ChatGPT workspace;
- периодически обновляйте Desktop Commander и tunnel-client после проверки совместимости.

Проект специально не настраивает постоянный фоновый сервис.
## Troubleshooting

### `rc-mcp` не найдена

Закройте PowerShell и откройте новое окно.

Либо в текущем окне выполните:

```powershell
. $PROFILE
```

### Tunnel не виден в ChatGPT или приложение MCP не создаётся

Проверьте:
- tunnel связан с нужным ChatGPT workspace, а не только с Platform Organization;
- у вашего Platform principal есть **Tunnels Read + Use**;
- `rc-mcp` сейчас запущен и окно PowerShell остаётся открытым;
- `tunnel-client doctor` проходит без ошибок;
- локальный health endpoint отвечает `200 ready`.

Диагностика из корня проекта:

```powershell
.\\.runtime\\tunnel-client\\tunnel-client.exe doctor --profile rdc-local --profile-dir .\\profiles --explain
Invoke-WebRequest http://127.0.0.1:8788/readyz -UseBasicParsing
(Invoke-WebRequest 'http://127.0.0.1:8788/health?details=true' -UseBasicParsing).Content
```

Ожидается `RESULT ok`, ответ `200 ready` и `ready: true`. Для stdio-конфигурации Desktop Commander в health должен быть `transport: stdio`, а дочерний MCP-процесс должен быть в состоянии `running`.

### ChatGPT видит старый набор MCP tools

Удалите/пересоздайте MCP app в ChatGPT или создайте новое подключение к тому же tunnel_id, чтобы ChatGPT заново выполнил tool discovery.

### Проверка tunnel-client вручную

```powershell
.\.runtime\tunnel-client\tunnel-client.exe doctor --profile rdc-local --profile-dir .\profiles --explain
```
## Структура проекта

```text
chatgpt-rdc-tunnel/
├─ README.md
├─ setup.ps1
├─ Start-RCMCP.ps1
├─ package.json
├─ package-lock.json
└─ .gitignore
```

После локальной установки появятся игнорируемые Git директории:

```text
node_modules/
.runtime/
.secrets/
profiles/
logs/
```

## Используемые проекты

Desktop Commander:
https://github.com/wonderwhy-er/DesktopCommanderMCP

OpenAI Secure MCP Tunnel:
https://github.com/openai/tunnel-client

OpenAI Secure MCP Tunnel documentation:
https://developers.openai.com/api/docs/guides/secure-mcp-tunnels

## Проверенная конфигурация

- Windows 11
- Node.js 24
- Desktop Commander 0.2.52
- OpenAI tunnel-client 0.0.15
- ChatGPT MCP connection через режим Tunnel
