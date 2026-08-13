#!/usr/bin/env bash
# ==============================================================================
# deploy-railway.sh — деплой veo_video_bot на Railway
#
# Usage:
#   chmod +x deploy-railway.sh
#   ./deploy-railway.sh
#
# Prerequisites:
#   1. Railway CLI:  curl -fsSL https://railway.app/install.sh | sh
#   2. railway login
#   3. railway init  (в корне проекта, выберите существующий проект или создайте новый)
#   4. Установите переменные в Railway Dashboard:
#        BOT_TOKEN     = ваш токен от @BotFather
#        TWA_URL      = https://ваше-app-name.up.railway.app
#        TWA_API_HOST = 0.0.0.0
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> VideoVeoBot: деплой на Railway"
echo ""

# --- Проверка Dockerfile ---
if [ ! -f "$SCRIPT_DIR/Dockerfile" ]; then
    echo "ERROR: Dockerfile не найден. Отмена."
    exit 1
fi

# --- Проверка Railway CLI ---
if ! command -v railway &> /dev/null; then
    echo "ERROR: Railway CLI не установлен."
    echo "Установите: curl -fsSL https://railway.app/install.sh | sh"
    echo "Затем: railway login"
    exit 1
fi

# --- Проверка что проект инициализирован ---
if ! railway status &> /dev/null; then
    echo "ERROR: Railway проект не инициализирован."
    echo "Запустите: railway init"
    exit 1
fi

echo "    Railway CLI: OK ($(railway --version 2>/dev/null || echo '?')"

# --- Проверка переменных ---
echo ""
echo "==> Проверка переменных окружения..."
MISSING=""
for var in BOT_TOKEN TWA_URL; do
    val=$(railway variables get "$var" 2>/dev/null || true)
    if [ -z "$val" ]; then
        echo "    ⚠ $var — НЕ установлен (нужно в Railway Dashboard)"
        MISSING=1
    else
        echo "    ✓ $var установлен"
    fi
done

if [ -n "$MISSING" ]; then
    echo ""
    echo "ERROR: не все переменные установлены."
    echo "Откройте Railway Dashboard → Variables и добавьте:"
    echo "  BOT_TOKEN=..."
    echo "  TWA_URL=https://ваше-app-name.up.railway.app"
    exit 1
fi

# --- Деплой ---
echo ""
echo "==> Деплой..."
railway up

echo ""
echo "==> Получение URL..."
sleep 5
APP_URL=$(railway status 2>/dev/null | grep -o 'https://[^ ]*\.up\.railway\.app' | head -1 || echo "")
if [ -n "$APP_URL" ]; then
    echo "    Приложение: $APP_URL"
    echo ""
    echo "==> Обновите TWA_URL если нужно:"
    echo "    railway variables set TWA_URL=$APP_URL"
else
    echo "    URL не найден — проверьте в Railway Dashboard"
fi

echo ""
echo "==> DONE"
echo "    Проверьте логи: railway logs"
echo "    Health: $APP_URL/api/health"
