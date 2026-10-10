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
