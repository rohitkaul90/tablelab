# Brand Context

> This file is auto-loaded by all blog sub-skills. Last updated: 2026-06-29.
> Brand: **TableLab** (product) — operated by **MagpiQ** (Ontario sole proprietorship). Live at tablelab.app (Android + Web).

## Audience

- **Primary**: Serious recreational-to-semi-pro **live** poker players — cash and tournament (MTT) — who already track their results or know they should. Numerate, time-poor, and allergic to marketing BS. They value accuracy, data ownership, and tools that respect their intelligence.
- **Secondary**: Disciplined-curious players graduating from casual to deliberate tracking; live players who are curious about GTO but actively distrust "AI coaching" claims.
- **Expertise**: Mixed, leaning intermediate-to-advanced. Assume they know hero/villain, position, SPR, ICM, variance, and BB/100 — explain only what a specific piece is actually about.
- **Active problems**:
  - Tracking live cash + tournament results accurately — multi-currency, rebuys/add-ons, expenses, breaks — without living in a spreadsheet.
  - Knowing their **true** win-rate / ROI / BB-100 with honest sample-size context (not a number that's lying to them).
  - Reviewing specific hands to find leaks when there's no online HUD or hand history to lean on.
  - Bankroll management and variance for the stakes they actually play.
  - Getting strategic feedback on a spot they can trust — without buying into hype or a black box.
- **Common misconceptions**:
  - "An AI can solve poker the way a solver does." (A language model is not a CFR solver.)
  - "Trackers are only for online grinders with HUDs."
  - "GTO is an online thing; live is all reads" — or the reverse, that live should be played like a 100bb online sim.
  - "I've played a ton of sessions, so my win-rate is reliable." (Sample-size blindness.)

## Positioning

- **Mission**: Help live cash and tournament players track their results honestly and understand their game with solver-grounded analysis — no hype, no black box.
- **Distinctive POV**: **A language model is not a solver, and we say so out loud.** A real CFR solver (TexasSolver) produces the GTO numbers — equity, frequencies, EV. The AI does exactly two honest jobs: it turns those deterministic facts into plain-language explanations, and it reasons heuristically about spots a solver can't tractably handle (multiway, deep live context), always grounded by hard solver facts and never inventing GTO numbers. Being transparent about what each layer can and can't do **is** the product's edge.
- **What we are NOT**:
  - Not an "AI poker coach" that implies a chatbot solves poker.
  - Not an online HUD, datamining, or hand-history-grabbing tool.
  - Not a GTO trainer — *yet*. Coaching is an assist feature today; the product may grow into fuller coaching, and we'll say when it does.
  - Not a "get an edge / get rich" gambling-hype brand.
- **Competitors**:
  - **Live bankroll trackers** (Poker Bankroll Tracker, Poker Income, RunGood, Pokerbase, Poker Analytics): we add solver-grounded hand insight on top of clean tracking — not just charts — with a first-class live recorder and real multi-currency.
  - **GTO study tools** (GTO Wizard and similar): we're **live-first** and we track your actual results, and we're honest that the LLM *explains* while the solver *solves* — we don't dress an LLM up as a trainer.
  - **Raw solvers** (PioSolver, TexasSolver, GTO+): we make solver output legible and contextual in your pocket — no tree-building, no desktop session, decisions framed for the table you're actually at.

## Editorial Rules

### Always do
- Separate **solver output** (deterministic GTO facts) from **AI prose / heuristics** explicitly, every time both appear in a piece.
- Show the math with its assumptions — equity, EV, or frequency stated alongside SPR, ranges, and position, not floating free.
- Ground every strategic claim in either a solver result or a clearly-labeled heuristic; if it's a read or an opinion, call it that.
- Use real, checkable examples — actual hands, ranges, sample sizes — over hand-wavy generalities.
- Be honest about limits: when a spot is multiway or otherwise unsolvable, say the analysis is heuristic and why.
- Write to a numerate peer. Skip the 101 unless the article is explicitly a 101.

### Never do
- Imply the AI/LLM "solves" poker or computes GTO frequencies itself.
- Promise outcomes ("AI will fix your game," "crush your games," "guaranteed edge").
- Publish unsourced statistics or any invented solver number.
- Talk down to the reader, or pad with listicle filler and SEO throat-clearing.
- Treat poker as risk-free income or push an "always be grinding" message; respect bankroll reality and responsible play.

### Taboo phrases
*(AI-hype blocklist — these read as slop to a skeptical poker audience and must never appear)*
- "AI-powered coaching" / "AI poker coach" / "AI that solves poker"
- "GTO AI" / "our AI solver" / "the AI solves the spot" (the AI is **not** the solver)
- "powered by AI" / "powered by artificial intelligence" / "leverage AI to…" / "harness the power of AI"
- "revolutionary," "game-changing," "next-generation," "cutting-edge," "supercharge"
- "unlock your potential," "take your game to the next level," "AI will fix your game"
- "guaranteed profit," "guaranteed edge," "beat any game," "the secret to…"
- AI-slop connective tissue: "In today's fast-paced poker world," "It's no secret that," "Let's dive in," "game-changer," "in this article, we'll explore"

### Required disclosures
- **Method transparency**: wherever analysis is shown, state plainly that GTO outputs are deterministic (TexasSolver / CFR) and the AI is used only for explanation and for heuristic reasoning on spots solvers can't reach — grounded by the solver's facts.
- **Fallibility**: mirror the in-app line — analysis can be wrong; verify big decisions.
- **Not advice**: poker involves risk and variance; nothing is financial advice. Include a responsible-play note where relevant.
- **Affiliate / sponsorship**: disclose any paid relationship up front when present.

## Topic Scope

- **In scope** (pillars):
  1. **Bankroll & results** — variance, sample size, true win-rate, ROI, BB/100, multi-currency, session discipline.
  2. **Live cash & MTT strategy** — SPR, ranges, ICM, position, and the leaks that actually cost live players money.
  3. **The honest layer** — how solver-grounded analysis works, what GTO means for a live game, and where the AI helps vs. where it stays out of the way.
  4. **Product how-tos** — lighter-touch: getting value from the tracker, calculators, hand recorder, replayer.
- **Partial scope**: GTO theory deep-dives (only with a clear live-player angle); online-derived concepts (only when they transfer cleanly to live).
- **Out of scope**: online HUD / datamining tactics; gambling promotion or "how to get rich"; non-poker casino games; touting specific operators or rakeback deals.
- **Recurring formats**:
  - **Field Notes** — lessons pulled from real live sessions.
  - **Spot Check** — one hand broken down with the solver's numbers and the honest caveats.
  - **The Honest Layer** — plain explainers of how the tech (and the limits) actually work.
