# AI-first workflow log

This project was built with Claude Code and Cursor. Every AI-generated model was
checked with `dbt build` and row-count comparisons against RAW before commit.
This log records what the AI did well, what it got wrong, and how I caught it.

## Rules I followed

1. No AI-generated SQL is committed until `dbt build` passes and row counts match RAW.
2. The AI writes tests for its own models; I read every test myself.
3. The AI drafts YAML docs; I correct every metric definition by hand.
4. I never let AI decide grants, roles or security settings without reviewing them line by line.

## Log

| Date | Task | Tool | What AI did well | What it got wrong | How I caught it |
|---|---|---|---|---|---|
| 2026-10-10 | Week 1 scaffold: setup SQL, COPY INTO, staging models | Claude | Generated the full Week 1 scaffold, roles and grants, profiling queries | _fill in after you run it_ | _fill in_ |
| 2026-11-06 | Raw load re-run | Claude | Loader re-run gave SKIPPED / 0 files processed; verified idempotency with unchanged row counts | | |
| 2026-11-16 | Airflow `load_raw` task failure and retry | Claude | Read the task log, found the cause and fixed it in `docker-compose.yml`: the container copies the key in with `chmod 600` at startup. Verified by running the loader inside the container (row counts unchanged), then cleared the task to rerun | The Docker setup mounted the Windows key folder directly; the Snowflake connector rejects keys that are writable by group or others ("Insecure file permissions"), and Windows mounts always look world-writable | `load_raw` failed in the Airflow UI on the first scheduled run; the error was in the task log |
| 2026-11-16 | SQLFluff formatting for CI | Claude | Auto-formatted the 21 models with `sqlfluff fix` so they passed `sqlfluff lint` locally | Pinned SQLFluff `>=3.0` in `requirements.txt` (installed 4.5.0) but `<4.0` in CI (installed 3.5.0); the two versions format differently, so CI flagged 8 of the files that passed locally | The `lint` check failed on the PR; reproduced it by installing 3.5.0 in a scratch venv, then pinned `sqlfluff==4.5.0` in both places |

<!--
Add a row every time something notable happens. Aim for at least 5 real entries.
Good entries are specific: "joined payments at item level, doubling revenue;
caught by custom test comparing revenue to raw item total".
-->

## Interview stories (STAR) drawn from this log

1. **Speed:** which tasks AI sped up and roughly how much time it saved.
2. **AI was wrong:** a time my tests caught an AI mistake.
3. **Where I don't trust AI:** metric definitions, security settings, grants, and why.
4. **Teaching it:** how I would teach a teammate this workflow.
