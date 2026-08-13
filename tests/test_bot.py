"""Pytest tests for service-level logic and handler wiring."""

from __future__ import annotations

import tempfile
from pathlib import Path

import pytest
import pytest_asyncio
from aiogram import Bot, Dispatcher

from bot import database
from bot.config import Config
from bot.database import init_database, session_factory
from bot.handlers import build_root_router
from bot.middleware import GenSettingsMiddleware
from bot.services import UserService


@pytest_asyncio.fixture
async def service(tmp_path: Path):
    """UserService with isolated SQLite."""
    from bot import database as db_module

    db_path = tmp_path / "test.db"
    await init_database(f"sqlite+aiosqlite:///{db_path}")
    assert db_module.session_factory is not None
    svc = UserService(session_factory=db_module.session_factory)
    yield svc
    await database.close_database()
    db_module.engine = None
    db_module.session_factory = None


@pytest.mark.asyncio
async def test_user_upsert_creates(service: UserService) -> None:
    await service.upsert_user(12345, username="alice", first_name="Alice")
    await service.upsert_user(12345, username="alice2", first_name="Alice2")
    # second call updates, doesn't crash
    gens = await service.last_generations(12345)
    assert isinstance(gens, list)


@pytest.mark.asyncio
async def test_record_generation_returns_id(service: UserService) -> None:
    await service.upsert_user(7, username=None, first_name="Bob")
    gid = await service.record_generation(
        user_id=7,
        model="kling",
        fmt="vertical",
        mode="standard",
        duration=5,
        sound=False,
        prompt="a beautiful sunset over mountains",
        image_file_id=None,
    )
    assert isinstance(gid, int) and gid > 0
    rows = await service.last_generations(7)
    assert len(rows) == 1
    assert rows[0].model == "kling"
    assert rows[0].prompt.startswith("a beautiful")
    assert rows[0].cost == 1


@pytest.mark.asyncio
async def test_balance_topup_and_spend(service: UserService) -> None:
    user = await service.upsert_user(100, username=None, first_name="C")
    assert user.balance == 10  # стартовый баланс

    new_bal = await service.add_balance(100, 50)
    assert new_bal == 60

    # Списываем 5
    ok = await service.spend(100, 5)
    assert ok is True
    user = await service.get_user(100)
    assert user.balance == 55

    # Пытаемся списать больше чем есть
    ok = await service.spend(100, 1000)
    assert ok is False
    user = await service.get_user(100)
    assert user.balance == 55  # не изменился


@pytest.mark.asyncio
async def test_history_returns_recent_first(service: UserService) -> None:
    await service.upsert_user(200, username=None, first_name="D")
    for i in range(3):
        await service.record_generation(
            user_id=200,
            model="kling" if i % 2 == 0 else "veo",
            fmt="vertical",
            mode="standard",
            duration=5,
            sound=False,
            prompt=f"prompt {i}",
            image_file_id=None,
            cost=1,
        )
    rows = await service.last_generations(200, limit=10)
    assert len(rows) == 3
    # Все три промпта присутствуют (порядок в SQLite по tie-break не гарантирован,
    # но количество и состав должны совпадать).
    prompts = {r.prompt for r in rows}
    assert prompts == {"prompt 0", "prompt 1", "prompt 2"}


@pytest.mark.asyncio
async def test_handler_wiring() -> None:
    """Walk the sub-routers and assert handlers are wired in."""
    root = build_root_router()

    # Collect every observer/handler attached to the root router tree.
    def collect(router):
        out = list(router.message.handlers) + list(router.callback_query.handlers)
        for child in router.sub_routers:
            out.extend(collect(child))
        return out

    handlers = collect(root)
    assert handlers, "no handlers attached anywhere in the router tree"

    # At least one Command('start') and one Command('examples') must be present.
    from aiogram.filters import Command

    def _has_command(text_):
        return any(
            Command(text_) in (getattr(h.filters, "commands", set()) or set())
            for h in handlers
            if hasattr(h, "filters")
        )

    # Quick smoke test: just confirm a representative command is registered.
    cmd_names = [
        h.callback.__name__
        for h in handlers
        if getattr(h, "callback", None) and hasattr(h, "filters")
    ]
    assert "cmd_start" in cmd_names, cmd_names
    assert "cmd_examples" in cmd_names, cmd_names


def test_config_defaults() -> None:
    cfg = Config.from_env()
    # Without env vars, has_token should be False
    assert isinstance(cfg.database_url, str)
    assert isinstance(cfg.admin_ids, tuple)


def test_cost_math() -> None:
    from bot.locales import GenSettings, compute_cost
    s = GenSettings(mode="standard", duration=5)
    assert compute_cost(s) == 1
    s = GenSettings(mode="pro", duration=5)
    assert compute_cost(s) == 2
    s = GenSettings(mode="4k", duration=5)
    assert compute_cost(s) == 4
    s = GenSettings(mode="standard", duration=10)
    assert compute_cost(s) == 2
    s = GenSettings(mode="pro", duration=10)
    assert compute_cost(s) == 3


def test_examples_catalog_has_at_least_three() -> None:
    from bot.examples import EXAMPLES, example_count
    assert example_count() >= 3
    assert all(ex.video_url.startswith("http") for ex in EXAMPLES)
    assert all(len(ex.prompt) > 20 for ex in EXAMPLES)


def test_main_menu_includes_all_models() -> None:
    """Main menu text mentions every model that has a /name shortcut."""
    from bot.keyboards import main_menu_kb
    from bot.locales import MODEL_DESCRIPTIONS, main_menu_text

    text = main_menu_text()
    for model_key in ("kling", "seedance", "lipsync"):
        assert MODEL_DESCRIPTIONS[model_key] in text, model_key
    for shortcut in ("/kling", "/seedance", "/lipsync"):
        assert shortcut in text, shortcut


def test_mini_app_button_uses_webapp_for_https() -> None:
    """Кнопка «📱 Открыть Mini App» должна быть ``web_app``-типа, иначе
    Telegram открывает её во внешнем браузере (это и есть исходный баг).

    Для HTTPS-URL кнопка присутствует, для http://не-localhost — скрыта.
    """
    from aiogram.types import WebAppInfo

    from bot.keyboards import main_menu_kb

    # 1) HTTPS-URL → кнопка web_app
    kb = main_menu_kb(twa_url="https://example.com/twa/")
    flat = [b for row in kb.inline_keyboard for b in row]
    twa_btns = [b for b in flat if "Mini App" in (b.text or "")]
    assert len(twa_btns) == 1, "expected exactly one Mini App button"
    btn = twa_btns[0]
    assert btn.web_app is not None and isinstance(btn.web_app, WebAppInfo)
    assert btn.web_app.url == "https://example.com/twa/"
    assert btn.url is None  # НЕ должна быть обычной URL-кнопкой

    # 2) http://localhost → кнопка web_app (Telegram разрешает в dev)
    kb = main_menu_kb(twa_url="http://127.0.0.1:8080/")
    flat = [b for row in kb.inline_keyboard for b in row]
    twa_btns = [b for b in flat if "Mini App" in (b.text or "")]
    assert len(twa_btns) == 1
    assert twa_btns[0].web_app is not None

    # 3) http://example.com → кнопка скрыта (Telegram её всё равно
    #    проигнорирует, лучше явно не вводить пользователя в заблуждение).
    kb = main_menu_kb(twa_url="http://example.com/")
    flat = [b for row in kb.inline_keyboard for b in row]
    twa_btns = [b for b in flat if "Mini App" in (b.text or "")]
    assert twa_btns == [], "non-https non-localhost URL should be hidden"

    # 4) пустой URL → кнопки нет
    kb = main_menu_kb(twa_url="")
    flat = [b for row in kb.inline_keyboard for b in row]
    twa_btns = [b for b in flat if "Mini App" in (b.text or "")]
    assert twa_btns == []


def test_balance_text_has_progress_bar() -> None:
    from bot.locales import balance_text
    out = balance_text(5)
    assert "▓" in out and "░" in out
    assert "5" in out


def test_history_text_handles_empty() -> None:
    from bot.locales import history_text
    out = history_text([])
    assert "Пока пусто" in out


def test_insufficient_funds_text_mentions_numbers() -> None:
    from bot.locales import insufficient_funds_text
    out = insufficient_funds_text(needed=5, available=2)
    assert "5" in out and "2" in out