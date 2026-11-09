"""Build SQL that writes config/ui_texts.json into the active rubric_config row.

Usage:
  python scripts/build_ui_texts_sql.py                 -> supabase/migrations/0006_ui_texts.sql
  python scripts/build_ui_texts_sql.py --out FILE.sql  -> later text updates

The UI text keys are merged into rubric_config.content of the ACTIVE row
(top-level keys replaced; metric definitions untouched). Re-run safe.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "config" / "ui_texts.json"
DEFAULT_OUT = ROOT / "supabase" / "migrations" / "0006_ui_texts.sql"
REQUIRED = ["app_name", "language_select", "welcome", "background", "batch_complete", "thankyou"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    data = json.loads(SRC.read_text(encoding="utf-8"))
    data.pop("_comment", None)
    missing = [k for k in REQUIRED if k not in data]
    if missing:
        raise SystemExit(f"Missing keys in ui_texts.json: {missing}")
    for k in ["welcome", "background", "batch_complete", "thankyou"]:
        if set(data[k].keys()) != {"en", "tr"}:
            raise SystemExit(f"Key '{k}' must have exactly 'en' and 'tr'")
        if set(data[k]["en"].keys()) != set(data[k]["tr"].keys()):
            raise SystemExit(f"Key '{k}': en and tr sub-keys differ")

    body = json.dumps(data, ensure_ascii=False, indent=2)
    if "$json$" in body:
        raise SystemExit("Text must not contain $json$")
    sql = f"""-- ReqIQ-ANN: UI texts (ADD-02 v0.6 §7) -> active rubric_config row
-- GENERATED from config/ui_texts.json by scripts/build_ui_texts_sql.py. Do not edit by hand.
-- Run in Supabase SQL Editor. Re-run safe: replaces only the UI text keys.

BEGIN;

UPDATE rubric_config
SET content = content || $json${body}$json$::jsonb
WHERE is_active = TRUE;

-- Verify: expect 1 row, ui_texts_version = {data.get('ui_texts_version')}
SELECT version_label,
       content->>'ui_texts_version'        AS ui_texts_version,
       content->'app_name'->>'tr'          AS app_name_tr,
       content->'welcome'->'tr'->>'title'  AS welcome_title_tr
FROM rubric_config WHERE is_active = TRUE;

COMMIT;
"""
    args.out.write_text(sql, encoding="utf-8")
    print(f"Written: {args.out}")


if __name__ == "__main__":
    main()
