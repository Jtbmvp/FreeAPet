# Trade security regressions

Run `python3 tests/security-trade/run.py /path/to/luau`. Current findings in `build/sentinel-security-2026-11-04/HANDOFF.md`.

Actual TradeService source, synthetic engine/Home/profile adapters. No real saves or Studio calls. Crash cuts model independent profile-write completion; this is not an actual DataStore outage. An exit1 with reported FAILs identifies failing security expectations. Code errors instead show a stack trace before the case results.

Do not change src to make these checks pass as part of QA; Coder owns implementation. After Coder fixes the cases, rerun this suite and add real-client persistence/multiplayer evidence in the Atlas-assigned test window. Existing progression environment is reused by reading it, never modified. Source hashes and drift are recorded.
