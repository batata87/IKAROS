---
name: gameplay-qa-agent
description: Runs automated front UI gameplay simulation with Playwright and generates a bug report in build/qa. Use when the user asks for QA automation, gameplay testing, UI simulation, bug report generation, or regression checks before fixes.
---

# Gameplay QA Agent

## Goal
Simulate gameplay interactions on the front UI and produce a bug report that can be used to prioritize and fix defects.

## Standard Workflow
1. Ensure dependencies are installed:
   - `npm install`
   - `npm run qa:install-browsers` (once per machine)
2. Start the app server in one terminal:
   - `npm run dev`
3. Run automated gameplay simulation:
   - `npm run qa:gameplay`
4. Read generated reports:
   - `build/qa/bug-report.md`
   - `build/qa/bug-report.json`
5. Convert findings into fix tasks ordered by severity (`high` first).

## Scheduled Automation
- GitHub workflow `qa-scheduled.yml` runs gameplay QA three times daily (06:00, 12:00, 18:00 UTC).
- When defects are found, it automatically opens a GitHub issue with findings and dispatches `qa-autofix.yml`.
- `qa-autofix.yml` creates a safe follow-up PR with deterministic maintenance updates and links back to the issue.

## Bug Report Rules
- Always include:
  - runtime exceptions,
  - console errors,
  - missing core UI (canvas not rendered),
  - screenshot path.
- Keep findings actionable with:
  - expected behavior,
  - observed behavior,
  - reproduction hint from event log.

## Triage Guidance
- `p0` (`critical`): player cannot start, control, or continue gameplay; app crash/hang; primary UI missing.
- `p1` (`high`): severe degradation in core loop or controls, but session may still continue.
- `p2` (`medium`): noticeable quality issues with non-blocking impact.
- `p3` (`low`): cosmetic or polish issues.

## Player Experience Definition
Player experience in this project focuses on front UI and gameplay continuity:
1. Fast and reliable entry into gameplay from the front screen.
2. Responsive controls during gameplay interactions.
3. Clear, accurate, and stable UI feedback (canvas, HUD, overlays).
4. No crashes, lockups, or repeated blocking errors.

## QA Coverage Plan
- Boot/render coverage: page and gameplay canvas render correctly.
- Entry flow coverage: front screen can transition into playable state.
- Input loop coverage: repeated keyboard/mouse interactions are accepted.
- Stability coverage: runtime exceptions and console errors are captured.
- Visual evidence: screenshot artifact for every run.

## Handoff to Fixing Agent
When this QA skill reports defects, pass the top findings to the coding workflow and fix in this order:
1. P0 defects (crashes, blocked gameplay, missing critical UI).
2. P1 defects (major gameplay degradation).
3. P2 defects (quality issues affecting feel/clarity).
4. P3 defects (polish).

