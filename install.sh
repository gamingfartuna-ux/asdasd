#!/usr/bin/env bash
# ==============================================================================
# install.sh — установка системных зависимостей + Python-пакетов
#               для Debian/Ubuntu (и производных)
#
# Usage:  ./install.sh
#
# Что делает:
#   1. Обновляет apt и ставит системные пакеты (python3, python3-venv, git)
#   2. Создаёт виртуальное окружение (.venv)
#   3. Ставит Python-зависимости проекта (aiogram, aiohttp, etc.)
#   4. Проверяет что всё импортируется
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> VideoVeoBot: установка"
echo ""

# ==============================================================================
# 1. Системные пакеты (только если НЕ Windows / macOS)
# ==============================================================================
if [[ "$(uname -s)" == "Linux" ]] && command -v apt-get &> /dev/null; then

    echo "==> [1/4] Обновление apt..."
    sudo apt-get update -qq

    echo "==> [2/4] Установка системных пакетов..."
    NEEDED=()

    for pkg in python3 python3-venv python3-pip git curl; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            NEEDED+=("$pkg")
        else
            echo "    $pkg — уже установлен"
        fi
    done

    if [ ${#NEEDED[@]} -gt 0 ]; then
        echo "    Устанавливаем: ${NEEDED[*]}"
        # В Docker/CI-среде (Railway, Fly.io) sudo может отсутствовать —
        # проверяем, является ли текущий пользователь root.
        if [ "$(id -u)" = "0" ]; then
            apt-get install -y -qq "${NEEDED[@]}"
        else
            sudo apt-get install -y -qq "${NEEDED[@]}"
        fi
    fi

    echo "    Python3: $(python3 --version)"
    echo "    pip3:    $(pip3 --version 2>/dev/null | head -1 || echo 'не найден')"
    echo ""

# --- macOS ---
elif [[ "$(uname -s)" == "Darwin" ]]; then
    echo "==> [1/4] macOS detected — проверка Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "    ERROR: Homebrew не найден. Установите: https://brew.sh"
        exit 1
    fi
    for pkg in python@3.11 git curl; do
        if ! brew list "$pkg" &> /dev/null; then
            echo "    Устанавливаем: $pkg"
            brew install "$pkg" 2>/dev/null || true
        else
            echo "    $pkg — уже установлен"
        fi
    done
    echo ""

# --- Windows (Git-Bash / MSYS) ---
elif [[ "$(uname -s)" == *"MINGW"* || "$(uname -s)" == *"CYGWIN"* || "$OSTYPE" == "msys" ]]; then
    echo "==> [1/4] Windows detected — пропускаем системные пакеты"
    echo ""

else
    echo "==> [1/4] Неизвестная ОС: $(uname -s) — пропускаем"
    echo ""
fi

# ==============================================================================
# 2. Определяем Python и uv
# ==============================================================================
echo "==> [3/4] Поиск Python..."

PYTHON_BIN=""
PYTHON_CMD=""

# Пробуем найти лучший Python
for cmd in python3.11 python3.12 python3.13 python3 python; do
    if command -v "$cmd" &> /dev/null; then
        VER=$("$cmd" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
        if [[ "$VER" == "3.10" || "$VER" == "3.11" || "$VER" == "3.12" || "$VER" == "3.13" ]]; then
            PYTHON_BIN="$cmd"
            PYTHON_CMD="$cmd"
            echo "    Python: $cmd (v$VER)"
            break
        fi
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo "ERROR: Python 3.10+ не найден."
    echo "Установите Python: https://www.python.org/downloads/"
    exit 1
fi

# --- uv (быстрый pip-альтернатива, кэширует зависимости) ---
VENV_PY="$SCRIPT_DIR/.venv/bin/python"
UV_BIN="$SCRIPT_DIR/.venv/bin/uv"

if [ ! -f "$VENV_PY" ]; then
    echo "    Создаём .venv..."
    $PYTHON_CMD -m venv "$SCRIPT_DIR/.venv"
    echo "    OK"
fi

# Обновляем pip в venv
echo "    pip в .venv: $(ls $VENV_PY 2>/dev/null && echo 'OK' || echo 'отсутствует')"

# Ставим uv если его нет
if ! "$VENV_PY" -m pip install --quiet 2>/dev/null; then
    echo "    WARNING: проблема с pip в venv"
fi

# Пробуем uv
if command -v uv &> /dev/null; then
    echo "    Используем: uv"
    USE_UV=true
elif [ -f "$UV_BIN" ]; then
    echo "    Используем: uv (из .venv)"
    USE_UV=true
else
    echo "    Используем: pip"
    USE_UV=false
fi

# ==============================================================================
# 3. Устанавливаем Python-зависимости проекта
# ==============================================================================
echo "==> [4/4] Установка Python-зависимостей..."

if [ "$USE_UV" = true ]; then
    echo "    (через uv)"
    uv pip install --python "$VENV_PY" -e "$SCRIPT_DIR" 2>/dev/null || \
        "$VENV_PY" -m pip install --upgrade pip wheel setuptools -e "$SCRIPT_DIR"
else
    echo "    (через pip)"
    "$VENV_PY" -m pip install --upgrade pip wheel setuptools 2>/dev/null || true
    "$VENV_PY" -m pip install -e "$SCRIPT_DIR"
fi

# ==============================================================================
# 4. Проверка
# ==============================================================================
echo ""
echo "==> Проверка установки..."
ALL_OK=true

for pkg in aiogram sqlalchemy aiosqlite aiohttp dotenv; do
    if "$VENV_PY" -c "import $pkg" 2>/dev/null; then
        VER=$("$VENV_PY" -c "import $pkg; print($pkg.__version__)" 2>/dev/null || echo "?")
        echo "    $pkg — OK ($VER)"
    else
        echo "    $pkg — FAIL"
        ALL_OK=false
    fi
done

echo ""

if [ "$ALL_OK" = true ]; then
    echo "==> Установка завершена успешно!"
else
    echo "==> WARNING: некоторые пакеты не установились."
    echo "   Попробуйте: .venv/bin/pip install -e ."
fi

echo ""
echo "==> Следующий шаг:"
echo "   1. Заполните .env: cp .env.example .env  →  укажите BOT_TOKEN"
echo "   2. Для локального dev: TWA_URL=http://127.0.0.1:8080/"
echo "   3. Для продакшена (Railway): TWA_URL=https://ваше-приложение.up.railway.app"
echo "   4. Запустите: ./run.sh"
echo ""
