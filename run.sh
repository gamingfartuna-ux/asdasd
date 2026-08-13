#!/usr/bin/env bash
# ==============================================================================
# run.sh — запускает TWA API и Telegram-бота
#
# Usage: ./run.sh
#
# Запускает оба процесса в фоне и выводит логи в терминал.
# При остановке (Ctrl+C) убивает оба процесса.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_PY="$SCRIPT_DIR/.venv/Scripts/python.exe"

# --- Проверки ---
if [ ! -f "$VENV_PY" ]; then
    echo "ERROR: виртуальное окружение не найдено."
    echo "Запустите сначала: ./install.sh"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "ERROR: файл .env не найден."
    echo "Скопируйте .env.example → .env и заполните BOT_TOKEN."
    exit 1
fi

# Читаем BOT_TOKEN и TWA_URL из .env
BOT_TOKEN=$(grep '^BOT_TOKEN=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')
TWA_URL=$(grep '^TWA_URL=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')

if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "YOUR_BOT_TOKEN_HERE" ]; then
    echo "ERROR: BOT_TOKEN не задан в .env. Получите токен у @BotFather."
    exit 1
fi

# --- Dev-режим vs продакшен ---
IS_HTTP=false
if [[ "$TWA_URL" == http://* ]]; then
    IS_HTTP=true
fi

echo "==> VideoVeoBot: запуск"
echo ""
echo "    TWA URL : $TWA_URL"
echo "    Bot     : polling (bot id $(echo $BOT_TOKEN | cut -d: -f1))"
echo ""

if [ "$IS_HTTP" = true ]; then
    echo "    ⚠️  ВНИМАНИЕ: TWA_URL начинается с http://"
    echo "       Telegram Web App кнопки требуют HTTPS в продакшене."
    echo "       Локально бот будет работать, но кнопка '📱 Открыть Mini App'"
    echo "       не откроет приложение (только '❓ Справка' через web_app)."
    echo "       Для полного тестирования Mini App нужен HTTPS (ngrok, Cloudflare Tunnel и т.п.)"
    echo ""
fi

# --- Останавливаем старые процессы ---
echo "==> Остановка старых процессов (если есть)..."
pkill -f "api.py" 2>/dev/null || true
pkill -f "bot.py" 2>/dev/null || true
sleep 1
echo "    OK"
echo ""

# --- Запускаем TWA API ---
echo "==> Запуск TWA API (aiohttp)..."
"$VENV_PY" api.py &
API_PID=$!
echo "    PID: $API_PID"

# Ждём поднятия
sleep 3

if ! curl -sf http://127.0.0.1:8080/api/health > /dev/null 2>&1; then
    echo "    ERROR: TWA API не ответил. Проверьте логи."
    kill $API_PID 2>/dev/null || true
    exit 1
fi
echo "    TWA API OK: http://127.0.0.1:8080"
echo ""

# --- Запускаем Telegram-бота ---
echo "==> Запуск Telegram-бота..."
"$VENV_PY" bot.py &
BOT_PID=$!
echo "    PID: $BOT_PID"

sleep 3
echo ""

# --- Финальная информация ---
echo "================================================================================"
echo "  VideoVeoBot запущен"
echo "--------------------------------------------------------------------------------"
echo "  TWA API  → http://127.0.0.1:8080"
echo "  Bot      → polling"
echo ""
echo "  Эндпоинты документации:"
echo "    GET /api/docs             — индекс доступных документов"
echo "    GET /api/docs/wizard-flow — FSM wizard flow"
echo "    GET /api/docs/bot-commands"
echo "    GET /api/docs/handlers/<name>"
echo "    GET /api/docs/services/<name>"
echo "    GET /api/docs/config"
echo "================================================================================"
echo ""
echo "Для остановки нажмите Ctrl+C"
echo ""

# Ждём любой процесс — при выходе убиваем оба
# shellcheck disable=SC2086
wait $API_PID $BOT_PID
EXIT_CODE=$?

echo ""
echo "==> Остановка (PID API=$API_PID, BOT=$BOT_PID)"
kill $API_PID 2>/dev/null || true
kill $BOT_PID 2>/dev/null || true
exit $EXIT_CODE
