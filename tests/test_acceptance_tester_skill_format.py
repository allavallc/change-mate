"""Tests that verify the acceptance-tester skill documents the conventions it claims to teach."""
import os


SKILL_PATH = os.path.join(
    os.path.dirname(__file__), '..', 'skills', 'acceptance-tester', 'SKILL.md'
)
BOTHORDE_PATH = os.path.join(
    os.path.dirname(__file__), '..', 'bot-horde', 'BOTHORDE.md'
)


def _read(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()


def test_skill_has_frontmatter_version():
    content = _read(SKILL_PATH)
    assert content.startswith('---'), "skill must start with YAML frontmatter"
    # Frontmatter ends at the second '---' line; everything between is fair game.
    end = content.find('\n---', 3)
    assert end != -1, "skill frontmatter block must close with ---"
    frontmatter = content[:end]
    assert 'name: acceptance-tester' in frontmatter, "frontmatter name must be acceptance-tester"
    assert 'version:' in frontmatter, "frontmatter must include a version line"


def test_skill_documents_tester_not_equal_dev_rule():
    content = _read(SKILL_PATH)
    assert 'tester' in content.lower() and 'dev' in content.lower(), \
        "skill must document the tester != dev bot rule"
    assert 'self-approval' in content.lower() or 'refuse' in content.lower(), \
        "skill must explain why self-approval is refused"


def test_skill_documents_both_outcome_paths():
    content = _read(SKILL_PATH)
    assert 'accepted' in content.lower(), "skill must cover the approve/accepted path"
    assert 'rejected' in content.lower(), "skill must cover the reject/rejected path"


def test_skill_documents_provenance_trailers():
    content = _read(SKILL_PATH)
    assert 'Model:' in content, "skill must document the Model: commit trailer"
    assert 'Trigger:' in content, "skill must document the Trigger: commit trailer"
    assert 'BH-XXX accepted' in content and 'BH-XXX rejected' in content, \
        "skill must show both accepted and rejected Trigger: examples"


def test_skill_points_to_bothorde_for_full_workflow():
    content = _read(SKILL_PATH)
    assert 'BOTHORDE.md' in content, \
        "skill must reference BOTHORDE.md for the full workflow spec"


def test_bothorde_references_acceptance_tester_skill():
    content = _read(BOTHORDE_PATH)
    assert 'acceptance-tester' in content, \
        "BOTHORDE.md Acceptance loop section must point to the acceptance-tester skill as the bot-tester entry point"
