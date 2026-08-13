#!/usr/bin/env bash
# ==============================================================================
# install.sh — создаёт виртуальное окружение и устанавливает зависимости
#              для проекта veo_video_bot
#
# Usage: ./install.sh
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/.venv"

echo "==> VideoVeoBot: установка зависимостей"
echo ""

# --- Python ---
if ! command -v python &> /dev/null && ! command -v python3 &> /dev/null; then
    echo "ERROR: Python не найден. Установите Python 3.10+ и добавьте в PATH."
    echo "   https://www.python.org/downloads/"
    exit 1
fi
PYTHON_BIN=$(command -v python 2>/dev/null || command -v python3)
echo "    Python: $PYTHON_BIN"

# --- Создаём venv ---
if [ -d "$VENV_DIR" ]; then
    echo "    .venv уже существует — пропускаем создание"
else
    echo "==> Создание виртуального окружения..."
    $PYTHON_BIN -m venv "$VENV_DIR"
    echo "    OK"
fi

VENV_PY="$VENV_DIR/Scripts/python.exe"
VENV_PIP="$VENV_DIR/Scripts/pip.exe"
VENV_UV="$VENV_DIR/Scripts/uv.exe"

# --- Определяем пакетный менеджер ---
if [ -f "$VENV_UV" ]; then
    PIP="$VENV_UV pip"
    echo "    Менеджер: uv"
else
    PIP="$VENV_PIP"
    echo "    Менеджер: pip"
fi

# --- Устанавливаем зависимости ---
echo "==> Установка зависимостей..."
$PIP install --upgrade pip wheel setuptools 2>/dev/null || true
$PIP install -e . 2>/dev/null || $PIP install -e .

# --- Проверка ---
echo ""
echo "==> Проверка установки..."
$PIP show aiogram sqlalchemy aiosqlite aiohttp python-dotenv 2>/dev/null | grep "^Name:" || true

$PIP show aiogram > /dev/null 2>&1 && echo "    aiogram  — OK" || echo "    aiogram  — FAIL"
$PIP show sqlalchemy > /dev/null 2>&1 && echo "    sqlalchemy — OK" || echo "    sqlalchemy — FAIL"
$PIP show aiosqlite > /dev/null 2>&1 && echo "    aiosqlite — OK" || echo "    aiosqlite — FAIL"
$PIP show aiohttp > /dev/null 2>&1 && echo "    aiohttp  — OK" || echo "    aiohttp  — FAIL"
$PIP show python-dotenv > /dev/null 2>&1 && echo "    python-dotenv — OK" || echo "    python-dotenv — FAIL"

echo ""
echo "==> Готово!"
echo ""
echo "   Следующий шаг:"
echo "   1. Заполните .env (скопируйте .env.example → .env, укажите BOT_TOKEN)"
echo "   2. Для dev-режима TWA_URL= http://127.0.0.1:8080/"
echo "   3. Для продакшена — HTTPS URL вашего сервера"
echo "   4. Запустите: ./run.sh"
echo ""
