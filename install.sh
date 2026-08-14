#!/usr/bin/env bash
set -e

apt-get update
apt-get install -y python3 python3-venv python3-pip git curl
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e .
cp .env.example .env 2>/dev/null || true
echo "Done. Edit .env and run: .venv/bin/python bot.py"
