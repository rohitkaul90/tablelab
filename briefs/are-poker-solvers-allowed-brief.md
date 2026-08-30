# Content Brief: Are Poker Solvers Allowed? (Post #7 — trend backlog item #2, The Honest Layer)

> Built on `BRAND.md` + `VOICE.md` + `brand/BLOG_STRATEGY.md` (Trend & Freshness Layer; backlog item #2) + persona `brand/tablelab.json`. Cluster: Pillar 2 (Live Strategy) with a hard cross-link into Cluster B (The Honest Layer). Format: **The Honest Layer** explainer. All research fetched **2026-08-30**.
>
> **Voice non-negotiables:** brand "we" + reader "you", full contractions, ≤30-word sentences, `TL;DR` label, insider register (SPR/ICM/HUD unglossed), no taboo phrases, never imply the LLM solves poker, no prose bold (house style since PR #58).

## Template

The Honest Layer explainer (question-led H2s, answer-first capsules, rule text quoted verbatim, one comparison table, two inline-SVG charts, FAQ + FAQPage JSON-LD). HTML cloned from `web/blog/how-to-beat-calling-stations.html`.

## Target Keywords

- **Primary:** `are poker solvers allowed`
- **Secondary:** `is using a solver cheating` · `poker RTA rules` · `what is RTA in poker` · `are HUDs allowed on PokerStars` / `GGPoker` · `can you use your phone at the poker table`
- **Question keywords:** Is it cheating to check a solver after a hand? · Are GTO charts allowed at the table? · Can I use a poker tracker app at a live table? · Are HUDs allowed in 2026? · Does the WSOP allow phones at the table?

## Search Intent

Informational with a guilty-conscience sub-intent: the searcher owns or is considering a solver/trainer/tracker and wants to know whether *they* are breaking a rule — not whether cheaters exist. Competitors answer "what is RTA" (glossary) or "RTA rules 2026" (operator-branded, dated). "Are poker solvers allowed" is the user's own question, year-free, and maps to TableLab's Skeptic-Studier segment.

**Why it survives the news decay:** the answer is rule text (PokerStars categories, GGPoker policy, TDA Rule 5, WSOP Rule 64, WSOP Live-Action Rule 21), not the news.

## Content Parameters

- Words: ~2,400 (spoke; ≥1,500 minimum)
- H2s: 8 (6 questions = 75%)
- Charts: 2 inline SVG · Table: 1 (`.compare-wrap`)
- Internal links: ≥5 in-cluster · Sources: ≥12 tier 1–2
- FAQ: 6 items, `<details>` + FAQPage JSON-LD
- Readability: Flesch grade 8–11, ease 50–65

## Recommended Title

- **H1:** Are Poker Solvers Allowed? Where the Line Is, Online and Live
- `<title>`: Are Poker Solvers Allowed? Online and Live Rules — TableLab
- Alt 1: Is Using a Solver Cheating? The Study-vs-Table Line, in the Operators' Own Words
- Alt 2: Which Poker Tools Are Allowed: Solvers, Trackers, HUDs, and Your Phone at the Table
- **Slug:** `/blog/are-poker-solvers-allowed` (no trailing slash)
- Kicker / `articleSection`: The Honest Layer · Byline: By Rohit Kaul · <publish date> · 11 min read

## Meta Description (149 chars)

Solvers, trainers, and trackers are allowed away from the table. Open one mid-hand and it's RTA. The exact rule text from PokerStars, GGPoker, TDA and WSOP.

## Hero Banner

Kicker THE HONEST LAYER · line 1 "Allowed at your desk." · line 2 "Banned at the table." · pill "solvers · trackers · charts · phones — the exact rule text".

## TL;DR Draft

Solvers, trainers, and trackers are allowed — away from the table. Every major operator draws the same line: PokerStars lists solvers under tools "prohibited while our software is running," GGPoker's policy says every decision "should be made free of any external assistance," and GTO Wizard's own terms bar use "during a live poker game." Live, the 2024 TDA rules say strategy tools "may not be used at the table," and the 2026 WSOP cash-game rules name "solver output" explicitly. Intent doesn't save you: a UK pro lost a £40,000 sponsorship in February 2026 for checking hands *after* they were played with the client open. TableLab is built for the allowed side of that line — post-session review — and this post shows you where the line sits, in the rule-writers' own words.

## Where the 2026 peg lives (and only there)

1. **Intro para 2:** WSOP Online 2026 is running on GGPoker right now (Aug 16 – Sep 29), the platform that suspended 31 accounts with GTO Wizard's help — and the WSOP just named GTO Wizard its Official Poker Training Partner, with an "Optimal Play" graphic on the broadcast. Solver on the broadcast, solver banned in the room.
2. **Hero banner** (above).
3. **One scoped H2:** "Why 2026 is the year the line got enforced."

**Decay review date: 2026-09-30** (day after WSOP Online ends — the intro's "running right now" goes stale). At review: intro → past tense, keep the H2 as history, bump `article:modified_time` + JSON-LD `dateModified` + sitemap `lastmod` together.

## Information Gain Opportunities (the post's spine — no competitor does these)

1. Quotes the live **cash-game** rule: WSOP 2026 Live-Action Rule 21 names "solver output".
2. Puts PokerStars' three categories beside GGPoker's v20260313 policy and shows the **preflop-chart disagreement**.
3. Quotes the **vendor's own terms** (GTO Wizard §7.1 / §7.2 — the vendor confirms board searches to operators).
4. Uses the **Clack** case to answer "I only checked it after the hand."
5. Tells a **tracker/study-app** user where their phone stands at a live table (TDA 5B/5C/5D).

## Content Outline

### Introduction (130–160 words)
Hook: WSOP Online is running on GGPoker right now, and the WSOP broadcast shows GTO Wizard's "Optimal Play" graphic on final-table hands — while the same tool, open at the same table, is a bannable offence. If you study with solvers, the fair question is: which side of the line am I on? Promise: the rule text online and live, the cases that define "during play," and what it means for a phone with a study app on it. TL;DR box.

### H2 1: Are poker solvers allowed? (260–320 words)
**Capsule:** Yes — as study tools. No operator bans owning or running a solver; every major one bans using it while you're in a hand. PokerStars files solvers under tools "prohibited while our software is running," and GTO Wizard's terms say users "must not use Service during a live poker game, including a poker game conducted online." The line is *when*, not *what*.
Facts: PokerStars three categories (F1–F3); GTO Wizard Terms §7.1 (F9); RTA definition (F11).

### H2 2: What counts as real-time assistance? (300–360 words)
**Capsule:** Anything that influences a decision while a hand is live: solver output, range or ICM calculators, push/fold charts, a friend on Discord. GGPoker's current Security Ecology Policy goes furthest: "Referring to charts of any kind during play is strictly prohibited." PokerStars still permits "simple table-based starting hand charts" for unopened pots — the one place the two disagree.
Cover: software vs reference material vs human help; the chart split; HUDs as a separate category (own-play data permitted on Stars, prohibited on GG) → link `/blog/how-to-read-players-without-a-hud`.
`.callout` — Our read: the operators aren't banning maths; they're banning *outsourced* maths. If the number came from your head, it's poker. If it came from a screen during the hand, it's RTA.
Facts: F3, F4, F11.

### H2 3: What do the big sites actually say? (340–400 words)
**Capsule:** Same principle, different wording. PokerStars sorts tools into permitted, prohibited at all times, and permitted-but-not-while-the-client-runs. GGPoker bans RTA, bots, solvers, charts, and third-party HUDs outright, with "PERMANENT BAN, CONFISCATION OF FUNDS" as the stated penalty. HUD policy is where sites diverge most.
**Table** (`.compare-wrap`): rows Solver (study, client closed) / Solver (client open) / Simple preflop chart during play / Third-party HUD / Tracker (post-session) / Datamining; columns PokerStars / GGPoker / WPT Global & ACR (HUD stance only, GipsyTeam — labelled secondary). Use ✓ / ✗ / "own-play only" cells with a footnote line.
Facts: F1–F4, F23.

### H2 4: What are the rules at a live table? (380–440 words)
**Capsule:** Stricter than online, and written down. TDA Rule 5D (2024): "Betting apps, charts, and other poker strategy tools may not be used at the table." WSOP 2026 Rule 64(g) bars "betting apps, gaming charts, or any poker information tool while involved in a hand," and 64(d) extends the ban to spectators in the room. Even WSOP cash games now name "solver output" in Rule 21.
Cover: TDA 5B (no devices resting on the table), 5C (live hand = no device interaction), 5D; WSOP 63 (nothing on the table), 64(b) (approved devices must not "contain or use artificial intelligence or any other type of electronic assistance"), 64(c) devices removed at the final three tables, 64(d) charts/apps/AI banned in the room incl. spectators, 64(g) + the WSOP LIVE / WSOP.com / Caesars app carve-out, 64(a) quotes NRS 465.075; Live-Action Rule 21 (smart watches, ear pieces; removal / forfeiture / permanent ban), Rule 27, Rule 82 (phone use "discouraged").
Facts: F13, F15, F16.

### H2 5: Why 2026 is the year the line got enforced (340–400 words) — THE scoped news section
**Capsule:** Detection moved from "we'll notice" to "we can timestamp it." GTO Wizard's Fair Play Check returns the exact time a board was solved; GGPoker used it to suspend 31 accounts on the first day of their partnership, announced March 2025. In 2026 an iPoker suspension cost a UK pro a £40,000 deal, and the WSOP put GTO Wizard on its broadcast while banning it in the room.
Timeline (Chart 2): Sep 2020 GG bans 40 / warns 40 / confiscates $1,175,305 from 13 / reimburses 4,329 → Sep 2023 Fair Play Check + WPN & WPT Global partnerships → Oct 2023 PokerStars says 95% of RTA is caught proactively → Oct 2024 TDA Rule 5 rewrite → Dec 2024 WSOP "electronic assistance" rule → Mar 2025 GG × GTO Wizard, 31 accounts → Feb 2026 Clack → Jun 2026 WSOP × GTO Wizard training partner → Aug–Sep 2026 WSOP Online on GGPoker.
Chart 1 (GG 2020 sweep bars) sits here too.
Facts: F5–F8, F10, F12, F14, F17, F20, F21.

### H2 6: Does "I only checked it after the hand" count? (300–360 words)
**Capsule:** On most sites, yes. Thomas Clack's own account — "After a hand had been played, I looked it up to see if I played it well… I had it open, which was silly" — still cost him a £40,000 Grosvenor sponsorship after an iPoker suspension, because the rule is about the tool being open while the client runs, not about intent. Nacho Barbero kept his ACR seat only after a hand-by-hand investigation.
Cover: PokerStars "while our software is running" wording; GTO Wizard §7.2 — the vendor will confirm to an operator whether a board was searched at a given time (a witness, not an ally); Barbero as the cleared-but-investigated contrast; practical rule: close the client, then study.
Facts: F1, F9, F17, F18.

### H2 7: Where does a tracker and study app like TableLab sit? (280–340 words)
**Capsule:** On the allowed side, by design. TableLab has no online-client integration, no HUD, and no hand-history scraping; the hand recorder, the GTO library, and the AI review are post-session tools. At a live table the only thing you'd touch mid-session is the session logger — and TDA 5B/5C make that a between-hands, phone-off-the-table activity, so treat it that way.
Disclosure paragraph (verbatim below). Phone-at-live-table guidance: log rebuys/breaks with your cards in the muck; never with a live hand; never resting on the table; at the WSOP, nothing once you reach three tables.
Links: `/gto-library` ("a solved GTO library of 26,325 spots"), `/about#how-analysis-works`, `/blog/can-ai-solve-poker` ("a language model is not a solver"), `/blog/good-live-poker-win-rate` ("your tracked win rate").

**Disclosure paragraph:** Where we sit: TableLab is a bankroll tracker with a hand recorder, a browsable GTO library, and AI hand review. The GTO numbers come from a real CFR solver (TexasSolver) we run offline; the AI only explains those numbers and reasons about spots a solver can't cover, and it's barred from stating a frequency it wasn't given — a language model is not a solver. Nothing in the app connects to an online client, reads a table, or shows opponent stats, and every review happens after the session. That's the allowed side of every policy quoted above. Two honest caveats: the analysis can be wrong, so verify big decisions; and at a live table your phone is subject to the house rule, not ours — log between hands, keep it off the felt, and if the floor says put it away, put it away.

### H2 8: How do you study with solvers without crossing the line? (220–280 words)
**Capsule:** Four habits keep you clean everywhere: study with the poker client closed; keep charts off the desk and off the table; review hands after the session, not between them; and at a live venue, assume the house rule is TDA 5 unless posted otherwise. If a rule is ambiguous, the floor decides — and "I didn't mean to" hasn't saved anyone yet.
Bulleted checklist; one line on Fair Play Check as something players can use against suspected RTA (app.gtowizard.com/fairplay). Optional link `/variance-calculator`.

### FAQ (6)
1. Are poker solvers allowed? — Yes, for study. PokerStars: "prohibited while our software is running"; GGPoker: no "external assistance" during play; GTO Wizard's terms: not "during a live poker game." Own one, run one, review with one — just not with a hand in progress.
2. Is using a solver cheating? — During a hand, yes: that's RTA, and every major site treats it as cheating with permanent bans and fund confiscation. After the session with the client closed, it's how everyone serious studies.
3. Can I check a hand in a solver between hands or on a break? — Don't. Thomas Clack said he looked hands up "after a hand had been played" and still lost a £40,000 sponsorship after an iPoker suspension in 2026. The rule keys on the tool being open while you're playing, not on intent.
4. Are HUDs allowed in 2026? — Depends on the site. PokerStars permits HUDs built only from hands you played yourself; GGPoker and WPT Global prohibit third-party HUDs. Live, there's no HUD — you build reads by hand.
5. Can I use my phone at a live poker table? — Under the 2024 TDA rules: not with a live hand (5C), never resting on the table (5B), never for strategy tools (5D). The 2026 WSOP goes further: devices removed at the final three tables; charts, apps, and AI banned in the room for players and spectators.
6. Is a bankroll tracker app allowed? — Yes. Trackers don't touch the hand in progress. Online, PokerStars permits tools that use "only information that you have accumulated through your own play"; live, log between hands with the phone off the felt.

### The bottom line (100–130 words)
Solvers compute; you decide. The line every rule-writer draws is *when*, not *what*. TableLab lives after the session. Single CTA.

## Verified facts table (fetched 2026-08-30) — the ONLY numbers/quotes allowed

| # | Claim | Source URL | Quote (verbatim-ish) |
|---|---|---|---|
| F1 | PokerStars policy has three categories | https://www.pokerstars.com/poker/room/prohibited/ | "Permitted Tools and Services"; "Tools and Services Prohibited at All Times"; "Permitted Tools and Services that are Prohibited While Our Software is Running" |
| F2 | PokerStars: solver-class tools prohibited while client runs | same | "Tools or services that compute advanced equity calculations, such as range vs range simulators, ICM or Nash Equilibrium-based programs" |
| F3 | PokerStars: simple charts OK; HUDs only from own play; datamining banned | same | "simple table-based starting hand charts advising on what hands to play or not in unopened pots"; "make use of only information that you have accumulated through your own play"; "The practice of datamining hands … is prohibited" |
| F4 | GGPoker Security Ecology Policy (v20260313) | https://ggpoker.com/network/security-ecology-policy/ | §2.2 "Every decision made at the poker table should be made free of any external assistance"; §2.3 "Referring to charts of any kind during play is strictly prohibited"; §2.4 "PERMANENT BAN, CONFISCATION OF FUNDS"; blocks tools that "influence gameplay decisions including … RTA, bots … solvers, charts, or HUDs"; "Tools or services that do not support or interact with GGPoker during gameplay will not be flagged" |
| F5 | GG × GTO Wizard partnership (announced March 2025) | https://ggpoker.com/blog/ggpoker-gto-wizard-join-forces/ · https://www.pokernews.com/news/2025/03/ggpoker-and-gto-wizard-team-up-to-keep-poker-fair-48110.htm | "suspiciously high usage of GTO Wizard during live play"; "Poker should be individual vs. individual, not individual vs. machine" |
| F6 | 31 accounts suspended on the first day of cooperation | https://blog.gtowizard.com/supporting_operators_in_protecting_online_poker/ (2025-05-27) | "31 fraudulent accounts suspended … on the first day of cooperation"; operators can "verify on a mass scale if boards dealt on their network were consulted in real-time on GTO Wizard" |
| F7 | Fair Play Check mechanics (Sep 2023) | https://blog.gtowizard.com/towards-a-safer-poker-ecosystem/ | "look up if a board was solved in GTO Wizard within a date interval, considering all strategically equivalent boards. If it was, the exact time when the board was solved is returned" |
| F8 | WPN + WPT Global partnered with GTO Wizard, Sep 2023 | https://www.poker.org/gto-wizard-teams-up-with-major-online-operators-to-help-combat-cheating/ | Nagy: "keeping online poker both fair and secure" |
| F9 | GTO Wizard Terms §7.1 / §7.2 | https://gtowizard.com/terms/ | §7.1 "User must not use Service during a live poker game, including a poker game conducted online (such as real time assistance)"; §7.2 "Provider may provide confirmation to third parties on an anonymous basis as to whether a particular combination of cards on the board has been searched for within the Service at a particular time" |
| F10 | GGPoker Sep 2020 enforcement numbers | https://www.pokernews.com/news/2020/09/ggpoker-responds-cheating-scandal-38050.htm · https://pokerfuse.com/news/poker-room-news/211765-ggpoker-reimburses-over-4000-players-following-recent-rta/ | 40 banned, 40 warned, $1,175,305 confiscated from 13 accounts, 4,329 players reimbursed (avg ≈ $272) |
| F11 | RTA definition | https://www.pokernews.com/news/2020/10/what-is-meant-by-real-time-assistance-rta-38054.htm | "Anything that assists a poker player in their decision-making while a cash game or tournament is in progress" |
| F12 | PokerStars *says* 95% of RTA caught proactively; integrity team ~20 years | https://pokerfuse.com/news/poker-room-news/219952-inside-pokerstars-arsenal-how-it-combats-rta/ (2023-10-06) | attribute as PokerStars' claim; "existential threat to online poker" |
| F13 | TDA 2024 Rules v1.0 (2024-10-09), Rule 5 | https://www.pokertda.com/view-poker-tda-rules/ | 5B "Phones and other devices may not rest on the table."; 5C "Players with live hands may not interact with or operate an electronic or communication device."; 5D "Betting apps, charts, and other poker strategy tools may not be used at the table. Nor may players receive or use poker strategy data from another person or source." |
| F14 | TDA rewrite context; WSOP Dec 2024 rule | https://www.poker.org/latest-news/whats-new-in-the-2024-tda-poker-tournament-rules-update-ayEOG4F466jL/ · https://www.pokernews.com/news/2024/12/wsop-paradise-makes-rule-change-47473.htm | 2024 WSOP wording: "Players and spectators are not allowed to use charts, apps, or any other form of electronic assistance in the tournament room." |
| F15 | WSOP 2026 Tournament Rules 63, 64(a–g) | https://assets.wsopcdn.com/wsop/1a72ba28-781c-409d-a9c3-5ca13c4c5718.pdf | 63: "No cell phones or other electronic communication device … can be placed on a poker table"; 64(b) approved devices must "not contain or use artificial intelligence or any other type of electronic assistance"; 64(c) devices removed at "the final three tables"; 64(d) "Participants and spectators are not allowed to use charts, apps, artificial intelligence or any other form of electronic assistance in the tournament room"; 64(g) "prohibited from using betting apps, gaming charts, or any poker information tool while involved in a hand" (carve-out: WSOP LIVE app, WSOP.com, Caesars Mobile Sports App); 64(a) quotes NRS 465.075 |
| F16 | WSOP 2026 Live-Action (cash) Rules 21, 27, 82 | https://assets.wsopcdn.com/wsop/853ee602-e1e9-4019-a0cf-381419d805c6.pdf | 21: "Real-Time Assistance is strictly prohibited. Players may not use any electronic device, software, or communication method to receive coaching, advice, analysis, solver output, or other strategic assistance about any live hand in play … smart watches, ear pieces …"; penalties "immediate removal … forfeiture of chips … permanent ban pending investigation"; 27: devices allowed if they don't interfere; 82: phone use "discouraged" |
| F17 | Clack case (Feb 2026) | https://www.pokernews.com/news/2026/02/thomas-clack-loses-grosvenor-poker-sponsorship-50567.htm | iPoker suspension; £40,000 package; "After a hand had been played, I looked it up to see if I played it well. I wasn't using it to affect my play, but I had it open, which was silly."; still allowed to play live at Grosvenor |
| F18 | Barbero / ACR (Feb 2025) | https://www.pokernews.com/news/2025/02/acr-releases-rta-allegation-findings-47877.htm · https://www.pokernews.com/news/2025/01/online-poker-cheating-acr-poker-47859.htm | ACR: "at no point did he use real-time assistance (RTA) to aid his or any other player's decision-making during live hands"; GTO Wizard open during The Venom, said to be for Discord coaching |
| F19 | ACR × GTO Wizard integration (Jun 2025) | https://www.acrpoker.eu/acr-poker/partnering-for-poker-integrity-how-acr-poker-and-gto-wizard-are-raising-the-bar-for-game-integrity/ | "Trust is the currency of online poker" |
| F20 | WSOP × GTO Wizard Official Poker Training Partner (Jun 2026); "Optimal Play" graphic | https://www.pokernews.com/news/2026/06/wsop-gto-wizard-official-poker-training-partner-2026-partner-51512.htm · https://blog.gtowizard.com/gto-wizard-at-the-2026-world-series-of-poker/ | graphic shows "the GTO-preferred action and whether the player chose to follow theory or deviate" |
| F21 | WSOP Online 2026 on GGPoker | https://www.pokernews.com/news/2026/08/ggpoker-unveils-2026-wsop-online-schedule-33-bracelets-52081.htm | Aug 16 – Sep 29; 33 bracelet events; $25M gtd Main Event |
| F22 | Holz on live bans — ambassador statement, not policy | https://www.cardplayer.com/poker-news/29886 (2025-03-04) | "That's the plan, and that's what will happen"; "WSOP officials declined to comment" |
| F23 | HUD stance by site (secondary) | https://www.gipsyteam.com/news/23-05-2026/huds-on-poker-sites | Stars/888/WPN/iPoker/Winamax permit; GG/WPT Global/CoinPoker prohibit |

## Could not verify / do NOT state

- 2p2 "NL500/NL1000 reg banned, 34-day investigation" (July 2026) — 403, unverified. Do not use.
- GGPoker's older T&C list "GTO solvers, range calculators, ICM analyzers" / basic-preflop-chart exception — only via PokerNews 2023; the current policy bans charts of any kind. State the current policy; if the older wording is used, attribute to PokerNews 2023 as prior wording.
- GTO Wizard lookup limits / delay figures — say only "built-in delays."
- Exact date of the 31-account action — write "announced March 2025."
- Kruse "$250k confiscated" / "$90,000 won" — don't state; use only the GG aggregate (F10).
- PokerStars 95% — operator claim, "PokerStars says."
- "Nevada law makes HUDs illegal" — only as "Nevada's device statute, as quoted in the WSOP rulebook (NRS 465.075)."
- Any Ontario/AGCO 2026 regulator move — none found. Do not claim.
- "2025 TDA rules" — current is 2024 v1.0. Cite 2024.
- WSOP rule numbers shift by year — cite 2026 numbering only.
- "PokerStars partnered with GTO Wizard" — FALSE (misinformation log). PT/HM merger — 2014, irrelevant.

## Visual Element Plan

- **Chart 1** (H2 5): horizontal bars "GGPoker's 2020 RTA sweep in numbers" — 40 banned · 40 warned · 13 funds confiscated · 4,329 reimbursed; annotation "$1,175,305 redistributed, ≈$272 average." `role="img"` + aria-label naming every value. Source line: PokerNews 2020-09-30 / pokerfuse 2020-10-07.
- **Chart 2** (H2 5): timeline lollipop 2020 → 2026 with the nine events above.
- **Table** (H2 3): tool × operator matrix.
- **Hero banner**: inline SVG per template.

## Internal Link Architecture

1. `/blog/can-ai-solve-poker` — "a language model is not a solver" (H2 7, bottom line)
2. `/gto-library` — "a solved GTO library of 26,325 spots" (H2 7)
3. `/about#how-analysis-works` — "how TableLab's analysis works" (disclosure)
4. `/blog/how-to-read-players-without-a-hud` — HUD paragraph (H2 2/3)
5. `/blog/good-live-poker-win-rate` — "your tracked win rate" (H2 7)
6. `/variance-calculator` — optional (H2 8 / bottom line)

**Sibling backlinks on publish:** `can-ai-solve-poker.html` (H2 "How an honest AI poker tool should be built" → this post) and `how-to-read-players-without-a-hud.html` (HUD section → this post). Bump their modified dates + sitemap lastmod together.

## E-E-A-T Signals

`#rohit` author entity + byline + `.author-box`; rule text quoted verbatim with the fetch date; the disclosure paragraph; `.disclaimer-line`: rule text quoted as published on the fetch date; operators change policies without notice — check the current page before you play. Nothing here is legal or financial advice.

## Sources list (`.sources`)

PokerStars prohibited-tools page · GGPoker Security Ecology Policy · GGPoker blog 2025-03-05 · PokerNews 2025-03-06 · GTO Wizard blog 2023-09-19 · GTO Wizard blog 2025-05-27 · GTO Wizard Terms · poker.org 2023-09-19 · PokerNews 2020-09-30 · pokerfuse 2020-10-07 · pokerfuse 2023-10-06 · PokerNews 2020-10 RTA explainer · Poker TDA 2024 Rules · WSOP 2026 Tournament Rules PDF · WSOP 2026 Live Action Rules PDF · poker.org 2024-10-11 · PokerNews 2024-12-01 · PokerNews 2026-02-06 · PokerNews 2025-02-03 · ACR blog 2025-06-09 · PokerNews 2026-06-11 · GTO Wizard blog 2026-06-24 · PokerNews 2026-08 (WSOP Online schedule) · GipsyTeam 2026-05-23 (secondary, HUD matrix only).

## Ship checklist (mirrors commit a6001c8, post #6)

1. `web/blog/are-poker-solvers-allowed.html`
2. `web/blog/index.html` — `.post-card` at top (kicker "The Honest Layer") + first `Blog.blogPost[]` entry
3. `web/sitemap.xml` — new `<url>` 0.7/monthly; bump `/blog/` lastmod
4. `web/llms.txt` — one dense bullet
5. `web/index.html` — noscript "Read more" `<li>`
6. Sibling backlinks (2) with date bumps
7. `brand/BLOG_STRATEGY.md` — backlog #2 shipped; decay row (review 2026-09-30)
8. `docs/` — do NOT hand-edit (deploy-web.yml regenerates on merge)
9. QA: reviewer ≥80 · factcheck vs this table · taboo grep · JSON-LD parse
