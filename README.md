# VideoVeoBot Demo

Демонстрационный Telegram-бот на **aiogram 3**, имитирующий функционал реального
VideoVeoBot (Kling / VEO / Seedance / Lipsync) и сопутствующий TWA Mini App в
том же визуальном стиле.

## Структура

```
veo_video_bot/
├── bot.py                       # entry point
├── bot/
│   ├── config.py                # Config dataclass + env loading
│   ├── database.py              # async SQLAlchemy engine/session
│   ├── models.py                # User, Generation ORM
│   ├── services/user_service.py # UserService — DB операции
│   ├── states/generation.py     # FSM StatesGroup
│   ├── keyboards/menus.py       # CallbackData + InlineKeyboardMarkups
│   ├── locales/texts.py         # тексты сообщений (HTML)
│   ├── middleware/gen_settings.py
│   ├── examples/catalog.py      # каталог заглушек-видео
│   └── handlers/
│       ├── start.py             # /start, /help, /cancel, /kling, /veo, /seedance, /lipsync
│       ├── menu.py              # главное меню, выбор модели
│       ├── generation.py        # wizard генерации
│       └── examples.py          # карусель примеров
├── twa/
│   ├── index.html               # Telegram Mini App (single-page)
│   ├── manifest.webmanifest
│   ├── css/style.css
│   ├── js/app.js
│   └── icons/                   # SVG иконки
├── tests/
│   └── test_bot.py              # ad-hoc pytest
├── pyproject.toml
├── .env.example
└── README.md
```

## Запуск бота

```bash
uv sync
export BOT_TOKEN=...
python bot.py
```

## Запуск TWA

Один процесс `python api.py` теперь отдаёт **и Mini App UI, и API** на одном
порту (`TWA_API_HOST:TWA_API_PORT`). Раньше нужно было параллельно держать
`python -m http.server 8080` для фронта и `api.py` для бэка — это конфликт
портов, теперь всё в одном месте.

```bash
# .env должен содержать BOT_TOKEN, TWA_URL=http://127.0.0.1:8080/
python api.py
# откройте http://localhost:8080/  — увидите Mini App UI
# внутри Telegram Mini App доступен по публичному HTTPS URL бота
# (см. BotFather → /setmenubutton или /myapps)
```

> **Важно:** кнопка `📱 Открыть Mini App` в боте использует `web_app`, и
> Telegram требует **HTTPS** (исключение — `http://localhost`/`127.0.0.1`
> для разработки). Для продакшена замените `TWA_URL` на публичный HTTPS
> (см. [официальные требования Telegram](https://github.com/telegram-mini-apps/telegram-apps/blob/master/apps/docs/platform/getting-app-link.md)).

## Что работает в демо

- **Главное меню** с моделями (Kling / VEO / Seedance / Lipsync) — повторяет скриншоты, плюс кнопки **💰 Баланс** и **📜 История**.
- **Карточка выбранной модели** с кнопками «Сгенерировать» / «Запустить Lipsync» и «Назад».
- **Wizard генерации** (Kling/VEO/Seedance): формат → режим → длительность → звук → изображение (опц.) → промпт → подтверждение с ценой и проверкой баланса.
- **Lipsync wizard** (отдельный flow): фото лица → голосовое/аудио → результат (3 генерации).
- **Баланс**: стартовый 10, пополнение через inline-кнопки (`+100`/`+500`), списание при подтверждении генерации, индикатор «останется X», отказ при нехватке средств.
- **История** (`/history`): последние 10 генераций с моделью, ценой, датой и превью промпта.
- **Команда `/examples`** — карусель из публичных sample-MP4 с навигацией ← / →.
- **TWA Mini App** в едином стиле: dark theme, фиолетовые акценты, кликабельные кнопки, **экран баланса с прогресс-баром** и **история в localStorage**.
- **Команды**: `/start`, `/help`, `/cancel`, `/kling`, `/veo`, `/seedance`, `/lipsync`, `/examples`, `/balance`, `/history`.
- **Хранение** в SQLite: пользователи (с балансом), история генераций (с `cost` и `video_url`).

## Заглушки видео

В `bot/examples/catalog.py` используются публичные sample MP4 с
`commondatastorage.googleapis.com` — короткие ролики, которые подставляются
как «примеры генераций». В реальной версии их нужно заменить ссылками на
результат работы моделей.