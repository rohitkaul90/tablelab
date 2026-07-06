# Distribution posts — "Poker Bankroll Management"

Repurposed from the blog post `web/blog/poker-bankroll-management.html`
(tablelab.app/blog/poker-bankroll-management), for **value-first, no-link** posting.

**Voice:** Rohit — real live cash reg (~3 yrs / ~3,200 hours tracked, quant background).
**Rule:** deliver the whole value inline. No link in the body. TableLab stays implicit
("I tracked every session"), which is true. Only share the link if someone asks — with an
honest disclosure ("Full disclosure, that's my site — not trying to sell anything").

All numbers match the blog's verified sources (Upswing, PokerNews, Primedope risk-of-ruin
formula + variance calcs, Chen & Ankenman, Fiedler). Keep them consistent if you edit.

---

## 1) Reddit text post (r/poker or a stakes-specific sub)

**Title:**
How many buy-ins do you actually need? (bankroll management without the hand-waving)

**Body:**

Every "how much roll for $1/2?" thread gets ten different answers, so here's the actual math and where the common numbers come from. I'm a live cash reg — tracked every session for ~3 years (~3,200 hours) — and I went down this rabbit hole for myself.

**TL;DR:** ~50 buy-ins for cash, 100+ for tournaments. It's risk-of-ruin math, not a vibe, and the real answer depends on your win rate and how swingy you run.

**The published guidelines**
- Cash: Upswing and most authorities say *at least 50 buy-ins*. At $1/2 with a $200 cap that's $10k.
- Tournaments: 100 buy-ins is the *minimum* most people cite; 200–500 if you play big fields.
- Plenty of live regs run leaner (20–30) because live deals way fewer hands/hour, so swings come slower. That's a personal risk choice, not a rule.

**The actual math**
Risk of ruin ≈ e^(-2 · WR · BR / SD²) (win rate, bankroll, standard deviation, all in bb/100). You don't need to compute it — the point is what it says. For a solid 3 bb/100 winner with ~85 bb/100 SD:
- 36 buy-ins → ~5% chance of going broke
- 48 → ~2%
- 56 → ~1%

Three levers: win more → need fewer; swing harder → need more; want to basically never go broke → need more.

**Why tournaments need so many more**
Only ~10–20% of the field cashes and the money's top-heavy, so per-tournament variance is ~5–10× a cash session. A real 30% ROI winner can go 200+ tournaments without a meaningful cash and still be crushing. That's a year-long dry spell that means nothing about your game.

**The part nobody wants to hear**
All of this assumes you're actually a winner. Most players aren't — in one big study 91% of the rake came from the top 10% of players. And the math needs *your* real win rate and SD, which you only know if you track. Memory is a garbage logbook; I thought I was running way worse than I actually was until I had the data.

Curious what buy-in counts people here actually run for their main game, and whether you drop down when you're stuck. Live variance in *calendar time* is brutal, so I run more conservative than most.

---

## 2) Two Plus Two thread (Live Low-stakes / Cash Game Strategy subforum)

**Title:**
Bankroll management: how many buy-ins you actually need (risk of ruin, by the numbers)

**Body:**

Bankroll threads always turn into a numbers fight, so here's a consolidated version with sources and the actual risk-of-ruin math. Background: live cash reg, ~3 years / ~3,200 hours tracked, quant background — so I'd rather get the math right than repeat rules of thumb.

**The two anchor numbers**
- Cash: at least 50 buy-ins (Upswing's guideline; $10k at $1/2). Conservative live players run 20–30, defensible given live's low hands/hour, but that's a risk choice, not a rule.
- MTTs: 100 buy-ins minimum (PokerNews), 200–500 for big-field regs.

**Risk of ruin**
The estimator most people are implicitly using is RoR = e^(-2 · WR · BR / SD²), popularized by Malmuth and derived properly in Chen & Ankenman's *Mathematics of Poker* (WR = win rate bb/100, BR = bankroll in bb, SD = std dev bb/100). Worked with a realistic profile (3 bb/100 winner, 85 bb/100 SD — Primedope's example):
- 36 buy-ins → 5% RoR
- 48 → 2%
- 56 → 1%

So the "50 buy-ins" folk wisdom lines up almost exactly with a ~1–2% risk of ruin for a modest winner. It isn't arbitrary. And because RoR is exponential in (WR·BR/SD²), a small change in your target ruin probability barely moves the buy-in count — going from 5% to 1% only costs ~20 buy-ins — while doubling your win rate or halving your variance moves it a lot.

**Tournaments**
Per-tournament SD runs ~5–10× a comparable cash session because of top-heavy payouts (~10–20% cash). A 30% ROI player can run 200+ MTTs without a significant cash and still be a long-term winner — run it through Primedope's or Galfond's variance calc and the distribution is sobering.

**Live vs online**
Live is ~25–30 hands/hour vs 60–100+ per online table. Same buy-in variance, but downswings last *far* longer in calendar time — a break-even stretch an online reg clears in a week can take a live player months. Rake and tips also quietly eat realized edge (a 20% pre-fee ROI can net ~10%).

**The input problem**
Every number above needs your real WR and SD. Estimating those from memory makes the RoR figure worthless — run your actual sample through a variance calculator.

Interested in how the live regs here weigh the calendar-time issue specifically. I've found it determines how conservative I need to be more than the raw buy-in count does.

*Sources: Upswing (bankroll), PokerNews (MTT), Primedope (RoR formula + variance calcs), Chen & Ankenman (Mathematics of Poker), Fiedler (rake concentration).*

---

## Posting etiquette (so these land, not bomb)

- **Post from your real account** with genuine comment history — not a fresh/burner account. On 2+2 especially, established posters get latitude.
- **No link in the body.** If someone asks "source?" / "where'd you write this up?", *then* reply with the blog link **plus an honest disclosure**: "Full disclosure, that's my site — happy to share, not trying to sell anything." That flips it from spam to generosity.
- **Don't cross-post identically the same day.** Same content in five places at once reads as coordinated. Space them out; tweak the opening line per venue.
- **Pick the right home.** r/poker for the general version; a stakes/live-specific sub if one fits. On 2+2, the Live Low-stakes or Cash Game Strategy subforum, not general chatter.
- **The test:** would this get upvotes with zero link attached? If yes, it builds reputation instead of burning it.

---

## Goal (why this over link-dropping)

The point is not blog traffic. It's (1) building Rohit's reputation as a real, knowledgeable
player, and (2) getting TableLab mentioned *by other people* — the off-page corroboration
signal that search + AI answers weigh most. Blog clicks are a side effect, not the target.
