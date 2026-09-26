"""Tests that `update.py` syncs Nanu's effect list before the staleness check, and flags the Dynamic RoR packs in a dry run."""

from core import delta
from tools import update_dynamic_ror_effects
from tools.update_dynamic_ror_effects import EffectSync
import update

DYNAMIC_RORS = next(unit for unit in delta.UNITS if unit.name == "dynamic_rors")
MODIFIED_ATTRIBUTES = next(unit for unit in delta.UNITS if unit.name == "modified_attributes")


def _record_sync_calls(monkeypatch, result):
    """Replace `sync_effects` with a stub that records its `write` argument.

    Args:
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used for patching.
        result (EffectSync): What the stub returns.

    Returns:
        The list the stub appends each `write` value to.
    """
    calls = []

    def fake_sync(write=True):
        calls.append(write)
        return result

    monkeypatch.setattr(update_dynamic_ror_effects, "sync_effects", fake_sync)
    return calls


def test_sync_is_skipped_when_no_dynamic_ror_pack_is_in_scope(monkeypatch):
    calls = _record_sync_calls(monkeypatch, EffectSync())
    assert update.sync_dynamic_ror_effects([MODIFIED_ATTRIBUTES], dry_run=False) is None
    assert calls == []


def test_sync_writes_only_outside_a_dry_run(monkeypatch):
    calls = _record_sync_calls(monkeypatch, EffectSync())
    update.sync_dynamic_ror_effects([DYNAMIC_RORS], dry_run=False)
    update.sync_dynamic_ror_effects([DYNAMIC_RORS], dry_run=True)
    assert calls == [True, False]


def test_dry_run_flags_pack_that_reads_a_changed_effect_list():
    check = delta.UnitCheck(DYNAMIC_RORS, stale=False)
    flagged = update.flag_pending_effect_sync(check, EffectSync(changed=True), dry_run=True)
    assert flagged.stale
    assert flagged.general
    assert flagged.reasons == ["Nanu's effect list changed"]


def test_real_run_and_unrelated_packs_are_not_flagged():
    check = delta.UnitCheck(DYNAMIC_RORS, stale=False)
    assert update.flag_pending_effect_sync(check, EffectSync(changed=True), dry_run=False) is check
    other = delta.UnitCheck(MODIFIED_ATTRIBUTES, stale=False)
    assert update.flag_pending_effect_sync(other, EffectSync(changed=True), dry_run=True) is other
    assert update.flag_pending_effect_sync(check, None, dry_run=True) is check
