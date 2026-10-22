---
trigger: always_on
---

# Mandatory project workflow

At the start of every task, before planning or editing, read the ENTIRE
`D:\AndroidScan\gallary\docs\ANTIGRAVITY_HANDOFF.md`.
Do not rely only on previous chat memory or a summary. Read the linked reports
relevant to the requested change. The user's latest instructions take precedence.

Before changing anything:
- Inspect the relevant current source and tests and check existing local changes.
- Trace the requested behaviour through the affected UI, API, engine and storage.
- Preserve existing uncommitted/untracked work and all real library, queue and
  checkpoint data. Do not reset, clean, overwrite or mass-format unrelated work.
- Make a focused change; do not rebuild an implemented feature or silently
  replace dependencies, Python environments or CUDA. Keep the terminal policy:
  give commands to the user unless execution is authorized in the active session.

After a change:
- Verify the affected behaviour with appropriate existing checks. Report exact
  passes, failures and untested cases; do not claim historical checks were rerun.
- Update `D:\AndroidScan\gallary\docs\ANTIGRAVITY_HANDOFF.md` before finishing:
  record changed files/behaviour, actual verification, known failures, remaining
  work and any phone/server state deliberately left paused or running.
- Keep the handoff's current-state facts accurate when changing models, paths,
  environments, architecture or acceptance status. Never write secrets into it.

Recorded baseline (2026-10-19; update when new evidence changes it): SDXL FP16
is installed and hash-verified; offline application loading passed. GPU/phone
refinement inference remains untested. Readiness alone does not prove inference.
The handoff records seven existing Restyle CPU test failures; do not hide them.
