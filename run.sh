#!/usr/bin/env bash
# ==============================================================================
# run.sh — запускает TWA API и Telegram-бота
#
# Usage: ./run.sh
#
# При Ctrl+C убивает оба процесса.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Определяем Python в .venv ---
if [ -f "$SCRIPT_DIR/.venv/bin/python" ]; then
    VENV_PY="$SCRIPT_DIR/.venv/bin/python"
elif [ -f "$SCRIPT_DIR/.venv/Scripts/python.exe" ]; then
    VENV_PY="$SCRIPT_DIR/.venv/Scripts/python.exe"
else
    echo "ERROR: .venv не найден. Запустите сначала: ./install.sh"
    exit 1
fi

# --- Проверки ---
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "ERROR: файл .env не найден."
    echo "Скопируйте .env.example → .env и заполните BOT_TOKEN."
    exit 1
fi

BOT_TOKEN=$(grep '^BOT_TOKEN=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')
if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "YOUR_BOT_TOKEN_HERE" ]; then
    echo "ERROR: BOT_TOKEN не задан в .env. Получите токен у @BotFather."
    exit 1
fi

TWA_URL=$(grep '^TWA_URL=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')
IS_HTTP=false
if [[ "$TWA_URL" == http://* ]]; then
    IS_HTTP=true
fi

echo "==> VideoVeoBot: запуск"
echo ""
echo "    TWA URL : $TWA_URL"
echo "    Bot     : polling"
echo ""

if [ "$IS_HTTP" = true ]; then
    echo "    ⚠️  TWA_URL начинается с http:// — Telegram Web App кнопки"
    echo "       требуют HTTPS в продакшене. Локально кнопка '📱 Открыть'"
    echo "       работать не будет. Для тестирования используйте ngrok"
    echo "       или Cloudflare Tunnel."
    echo ""
fi

# --- Останавливаем старые процессы ---
echo "==> Остановка старых процессов..."
for pidfile in "$SCRIPT_DIR/.api.pid" "$SCRIPT_DIR/.bot.pid"; do
    if [ -f "$pidfile" ]; then
        OLD_PID=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            echo "    Остановлен PID $OLD_PID"
        fi
        rm -f "$pidfile"
    fi
done
# На всякий случай pkill (работает и на Linux, и на macOS)
pkill -f "api.py" 2>/dev/null || true
pkill -f "bot.py" 2>/dev/null || true
sleep 1
echo "    OK"
echo ""

# --- Запускаем TWA API ---
echo "==> Запуск TWA API..."
"$VENV_PY" api.py &
API_PID=$!
echo "$API_PID" > "$SCRIPT_DIR/.api.pid"
echo "    PID: $API_PID"

sleep 3

if ! curl -sf http://127.0.0.1:8080/api/health > /dev/null 2>&1; then
    echo "    ERROR: TWA API не ответил на health-check."
    kill "$API_PID" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/.api.pid"
    exit 1
fi
echo "    TWA API OK: http://127.0.0.1:8080"
echo ""

# --- Запускаем бота ---
echo "==> Запуск Telegram-бота..."
"$VENV_PY" bot.py &
BOT_PID=$!
echo "$BOT_PID" > "$SCRIPT_DIR/.bot.pid"
echo "    PID: $BOT_PID"

sleep 2
echo ""

# --- Финальная информация ---
echo "================================================================================"
echo "  VideoVeoBot запущен"
echo "--------------------------------------------------------------------------------"
echo "  TWA API  → http://127.0.0.1:8080"
echo "  Bot      → polling"
echo ""
echo "  Документация (Mini App):"
echo "    GET /api/docs             — индекс"
echo "    GET /api/docs/wizard-flow — FSM flow"
echo "    GET /api/docs/bot-commands"
echo "    GET /api/docs/handlers/<name>"
echo "    GET /api/docs/services/<name>"
echo "================================================================================"
echo ""
echo "Для остановки нажмите Ctrl+C"
echo ""

# --- Ждём любой процесс, при выходе — останавливаем оба ---
trap 'echo ""; echo "==> Остановка..."; kill $(cat "$SCRIPT_DIR/.api.pid" 2>/dev/null) 2>/dev/null || true; kill $(cat "$SCRIPT_DIR/.bot.pid" 2>/dev/null) 2>/dev/null || true; rm -f "$SCRIPT_DIR/.api.pid" "$SCRIPT_DIR/.bot.pid"; exit 0' INT TERM

wait $API_PID $BOT_PID
