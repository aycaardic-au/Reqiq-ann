"""Build SQL that stores config/ui_texts.json as a new rubric_config version (needs migration 0018).

Usage:
  python scripts/build_ui_texts_sql.py                 -> supabase/migrations/0006_ui_texts.sql
  python scripts/build_ui_texts_sql.py --out FILE.sql  -> later text updates

The UI text keys replace the same top-level keys of the active content; the result becomes a new
active version and the previous version is kept (FR-CFG-VER-001). Running it twice creates no extra version.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "config" / "ui_texts.json"
DEFAULT_OUT = ROOT / "supabase" / "migrations" / "0006_ui_texts.sql"
REQUIRED = ["app_name", "consent", "declined", "form", "intro", "annotate", "annotate_rubric", "session_bar", "batch_complete", "thankyou", "common"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    data = json.loads(SRC.read_text(encoding="utf-8"))
    data.pop("_comment", None)
    missing = [k for k in REQUIRED if k not in data]
    if missing:
        raise SystemExit(f"Missing keys in ui_texts.json: {missing}")
    # D-23: screen texts are Turkish for every session; 'en' is optional.
    for k in REQUIRED[1:]:
        if "tr" not in data[k] or not set(data[k]) <= {"en", "tr"}:
            raise SystemExit(f"Key '{k}' must have 'tr' (and optionally 'en') only")
        if "en" in data[k] and set(data[k]["en"].keys()) != set(data[k]["tr"].keys()):
            raise SystemExit(f"Key '{k}': en and tr sub-keys differ")

    body = json.dumps(data, ensure_ascii=False, indent=2)
    if "$json$" in body:
        raise SystemExit("Text must not contain $json$")
    ver = data.get("ui_texts_version")
    sql = f"""-- ReqIQ-ANN: UI texts {ver} -> NEW rubric_config version (FR-CFG-VER-001, migration 0018)
-- GENERATED from config/ui_texts.json by scripts/build_ui_texts_sql.py. Do not edit by hand.
-- Run in Supabase SQL Editor. Creates a new active configuration version (the previous one is kept).
-- Alternative without SQL: admin panel -> İçe aktar -> Ekran metinleri.

SELECT _config_new_version($json${body}$json$::jsonb, NULL, 'ui_texts {ver}') AS new_version;

-- Verify: ui_texts_version = {ver}
SELECT version_label, content->>'ui_texts_version' AS ui_texts_version FROM rubric_config WHERE is_active = TRUE;
"""
    args.out.write_text(sql, encoding="utf-8")
    print(f"Written: {args.out}")


if __name__ == "__main__":
    main()
