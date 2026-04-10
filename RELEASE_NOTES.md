# Release Notes

## v0.0.1+b1
- Date: 2026-04-08T13:43:01.888Z
- Tune iOS-native gameplay responsiveness and safety behavior.
- Tighten mobile flow: menu alignment and upward gameplay safeguards.
- Prevent iOS menu tap carry-over from auto-releasing player.
- Fix level generator bool inference in cull logic.
- Further harden level generator against parse edge cases.
## v0.0.1+b2
- Date: 2026-04-08T13:55:06.695Z
- Add automated build stamping, release notes, and in-game build label.
- Tune iOS-native gameplay responsiveness and safety behavior.
- Tighten mobile flow: menu alignment and upward gameplay safeguards.
- Prevent iOS menu tap carry-over from auto-releasing player.
- Fix level generator bool inference in cull logic.
## v0.0.1+b3
- Date: 2026-04-09T08:57:23.609Z
- Add Notion release publishing hook and bump build stamp.
- Add automated build stamping, release notes, and in-game build label.
- Tune iOS-native gameplay responsiveness and safety behavior.
- Tighten mobile flow: menu alignment and upward gameplay safeguards.
- Prevent iOS menu tap carry-over from auto-releasing player.
## v0.0.1+b4
- Date: 2026-04-09T09:06:18.384Z
- Add Notion release publishing hook and bump build stamp.
- Add automated build stamping, release notes, and in-game build label.
- Tune iOS-native gameplay responsiveness and safety behavior.
- Tighten mobile flow: menu alignment and upward gameplay safeguards.
- Prevent iOS menu tap carry-over from auto-releasing player.
## v0.0.1+b5
- Date: 2026-04-09T09:29:43.360Z
- Add Notion release publishing hook and bump build stamp.
- Add automated build stamping, release notes, and in-game build label.
- Tune iOS-native gameplay responsiveness and safety behavior.
- Tighten mobile flow: menu alignment and upward gameplay safeguards.
- Prevent iOS menu tap carry-over from auto-releasing player.
## v0.0.1+b6
- Date: 2026-04-09T09:47:41.760Z
- Gameplay: reduced close-cluster circle spawning and made early anchor density easier to read.
- Gameplay: fixed timer fairness behavior at upper circles (countdown start/continuation logic).
- Gameplay: enforced up-only jump/capture flow to prevent downward recovery loops.
- Gameplay: added stronger anti-stuck and anti-endless-flight fail-safe checks.
- Camera: adjusted upward lead so upcoming circles remain visible.
- UI: welcome-screen alignment and build stamp placement corrected for iPhone aspect ratios.
## v0.0.1+b7
- Date: 2026-04-09T09:52:49.283Z
- Gameplay: anchor chain progression tuned to reduce early clutter and improve upward readability.
- Gameplay: countdown timer fairness improved so active anchor timer no longer stalls at upper heights once started.
- Gameplay: strictly upward movement enforcement (downward/backward dash paths now fail instead of drifting).
- Gameplay: anti-stuck/endless-flight safeguards tightened for dash and timeout states.
- Camera: upward lead offset added to keep upcoming circles visible near top of screen.
- UI: welcome-screen build stamp visibility and alignment corrected for iPhone layouts.
- Fix welcome build label visibility, spawn progression, and up-only dash flow; bump b6.
- Fix iPhone menu alignment and anchor spacing flow; bump build b5.
## v0.0.1+b8
- Date: 2026-04-10T08:36:07.559Z
- Gameplay: anchor chain progression tuned to reduce early clutter and improve upward readability.
- Gameplay: countdown timer fairness improved so active anchor timer no longer stalls at upper heights once started.
- Gameplay: strictly upward movement enforcement (downward/backward dash paths now fail instead of drifting).
- Gameplay: anti-stuck/endless-flight safeguards tightened for dash and timeout states.
- Camera: upward lead offset added to keep upcoming circles visible near top of screen.
- UI: welcome-screen build stamp visibility and alignment corrected for iPhone layouts.
- Fix Godot parse robustness in level generator.
- Overhaul mobile flow-state core loop for IKAROS.
## v0.0.1+b9
- Date: 2026-04-10T08:47:50.660Z
- Gameplay: anchor chain progression tuned to reduce early clutter and improve upward readability.
- Gameplay: countdown timer fairness improved so active anchor timer no longer stalls at upper heights once started.
- Gameplay: strictly upward movement enforcement (downward/backward dash paths now fail instead of drifting).
- Gameplay: anti-stuck/endless-flight safeguards tightened for dash and timeout states.
- Camera: upward lead offset added to keep upcoming circles visible near top of screen.
- UI: welcome-screen build stamp visibility and alignment corrected for iPhone layouts.
- Fix Godot type inference for forced LUX spawn position.
- Refactor mobile core loop for stability and smoothness.
## v0.0.1+b10
- Date: 2026-04-10T08:59:41.745Z
- Gameplay: anchor chain progression tuned to reduce early clutter and improve upward readability.
- Gameplay: countdown timer fairness improved so active anchor timer no longer stalls at upper heights once started.
- Gameplay: strictly upward movement enforcement (downward/backward dash paths now fail instead of drifting).
- Gameplay: anti-stuck/endless-flight safeguards tightened for dash and timeout states.
- Camera: upward lead offset added to keep upcoming circles visible near top of screen.
- UI: welcome-screen build stamp visibility and alignment corrected for iPhone layouts.
- Implement validated spawning and boundary safety net for iOS.
- Fix Godot type inference for forced LUX spawn position.
## v0.0.1+b11
- Date: 2026-04-10T10:47:39.552Z
- Gameplay: anchor chain progression tuned to reduce early clutter and improve upward readability.
- Gameplay: countdown timer fairness improved so active anchor timer no longer stalls at upper heights once started.
- Gameplay: strictly upward movement enforcement (downward/backward dash paths now fail instead of drifting).
- Gameplay: anti-stuck/endless-flight safeguards tightened for dash and timeout states.
- Camera: upward lead offset added to keep upcoming circles visible near top of screen.
- UI: welcome-screen build stamp visibility and alignment corrected for iPhone layouts.
- Rewrite gameplay to vertical-track spawning model.
- Implement validated spawning and boundary safety net for iOS.
## v0.0.1+b12
- Date: 2026-04-10T10:58:47.314Z
- Gameplay: anchor chain progression tuned to reduce early clutter and improve upward readability.
- Gameplay: countdown timer fairness improved so active anchor timer no longer stalls at upper heights once started.
- Gameplay: strictly upward movement enforcement (downward/backward dash paths now fail instead of drifting).
- Gameplay: anti-stuck/endless-flight safeguards tightened for dash and timeout states.
- Camera: upward lead offset added to keep upcoming circles visible near top of screen.
- UI: welcome-screen build stamp visibility and alignment corrected for iPhone layouts.
- Refactor movement flow with magnetic launches and forgiving captures.
- Rewrite gameplay to vertical-track spawning model.
## v0.0.1+b13
- Date: 2026-04-10T11:20:39.364Z
- Gameplay: anchor chain progression tuned to reduce early clutter and improve upward readability.
- Gameplay: countdown timer fairness improved so active anchor timer no longer stalls at upper heights once started.
- Gameplay: strictly upward movement enforcement (downward/backward dash paths now fail instead of drifting).
- Gameplay: anti-stuck/endless-flight safeguards tightened for dash and timeout states.
- Camera: upward lead offset added to keep upcoming circles visible near top of screen.
- UI: welcome-screen build stamp visibility and alignment corrected for iPhone layouts.
- Fix circle lifecycle crash risk and restore physics-first launches.
- Refactor movement flow with magnetic launches and forgiving captures.
