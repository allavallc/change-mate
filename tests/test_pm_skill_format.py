"""Tests that verify the PM skill documents the conventions it claims to teach."""
import os


SKILL_PATH = os.path.join(
    os.path.dirname(__file__), '..', 'skills', 'product-manager', 'SKILL.md'
)
HORDEOFBOTS_PATH = os.path.join(
    os.path.dirname(__file__), '..', 'horde-of-bots', 'HORDEOFBOTS.md'
)


def _read(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()


def test_skill_documents_model_trailer():
    assert 'Model:' in _read(SKILL_PATH), \
        "PM skill must document the Model: commit trailer"


def test_skill_documents_trigger_trailer():
    assert 'Trigger:' in _read(SKILL_PATH), \
        "PM skill must document the Trigger: commit trailer"


def test_skill_points_to_hordeofbots_for_provenance():
    content = _read(SKILL_PATH)
    assert 'HORDEOFBOTS.md' in content, \
        "PM skill must reference HORDEOFBOTS.md for the full provenance convention"
    assert 'Provenance' in content, \
        "PM skill must mention the 'Provenance' convention by name"


def test_hordeofbots_documents_full_trailer_format():
    content = _read(HORDEOFBOTS_PATH)
    assert 'Provenance trailers' in content, \
        "HORDEOFBOTS.md must have a 'Provenance trailers' section"
    assert 'Model:' in content and 'Trigger:' in content, \
        "HORDEOFBOTS.md must show both Model: and Trigger: trailers"
    for action in ('claim', 'done', 'edit', 'blocked', 'reclaim'):
        assert action in content, \
            f"Provenance section must include the '{action}' action"
