#!/usr/bin/env bash
set -e

.venv/bin/python api.py &
.venv/bin/python bot.py
