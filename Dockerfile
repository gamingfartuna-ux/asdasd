# ==============================================================================
# Dockerfile — Railway / Fly.io / любой Docker-хостинг
# ==============================================================================
FROM python:3.11-slim

LABEL org.opencontainers.image.title="VideoVeoBot"
LABEL org.opencontainers.image.description="Demo Telegram bot + TWA Mini App"

WORKDIR /app

# --- Системные зависимости ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
    && rm -rf /var/lib/apt/lists/*

# --- Копируем только зависимости сначала (кеширование слоёв) ---
COPY pyproject.toml uv.lock ./

# --- Python-зависимости (без sudo — мы уже root в контейнере) ---
RUN pip install --no-cache-dir uv && \
    uv pip install --system --no-cache-dir -e .

# supervisord для запуска api.py + bot.py в одном контейнере
RUN pip install --no-cache-dir supervisord

# --- Копируем весь проект ---
COPY . .

# --- Переменные окружения ---
# PORT и TWA_API_HOST задаются через Railway Dashboard
ENV PORT=8080
ENV TWA_API_HOST=0.0.0.0
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# --- Healthcheck ---
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf http://localhost:${PORT}/api/health || exit 1

EXPOSE ${PORT}

# Railway требует non-root пользователя
USER 1000

# supervisord.conf лежит рядом с проектом — копируем его в домашнюю папку
# (supervisord сам откроет его при запуске)
COPY --chown=1000 supervisord.conf /home/1000/supervisord.conf

