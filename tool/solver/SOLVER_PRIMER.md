# How a poker solver works — primer (TexasSolver + TableLab integration)

> Reference doc capturing the "how does a CFR solver actually work, end to end" walkthrough,
> so we don't re-derive it. Pairs with `tool/solver/README.md` (the bridge mechanics),
> `launch/SOLVER_ENGINE_LANDSCAPE.md` (build-vs-buy + license), and
> `launch/DECISION_CONTEXT_ENGINE.md` (how solver output calibrates the DCE FACTs).
>
> TL;DR — a solver is one giant recursive EV computation. Equity (`lib/equity/`) is the
> *leaf* evaluation; CFR is the iteration that finds the unexploitable strategy on top of it.
> Everything the DCE adds (EQR, SPR, MDF, board-volatility) are heuristic shortcuts that
> approximate quantities the solver computes exactly.

---

## 0. A solver does NOT solve preflop — it starts at the flop

TexasSolver (like PioSOLVER / GTO+) is a **postflop** solver. Preflop is collapsed into an
**input**: the two ranges that arrive at the flop, with weights = preflop frequencies. Those
ranges come from preflop charts / a separate preflop solver — in TableLab from
`gto_ranges.dart` via `chart_keys.dart` (exactly what `solver_input.dart` builds: `BTN open`
→ IP range, `BB call` → OOP range). The solver then solves the **flop → turn → river**
subgame exactly *within its abstraction*.

**Load-bearing for integration:** the solver's answer is only as good as the preflop ranges
fed in. Wrong ranges → confidently-precise-and-wrong.

---

## 1. Inputs (the whole problem statement)

Example used throughout: heads-up, single-raised pot, flop **9♥7♥2♠**, pot $20, effective
stack $100 behind → **SPR 5**. Hero = BTN (**IP**), villain = BB (**OOP**, acts first postflop).

| Input | Value | TexasSolver command |
|---|---|---|
| Board | 9♥7♥2♠ | `set_board 9h,7h,2s` |
| Pot | $20 | `set_pot 20` |
| Effective stack behind | $100 | `set_effective_stack 100` |
| IP range (BTN) | weighted combos | `set_range_ip ...` |
| OOP range (BB) | weighted combos | `set_range_oop ...` |
| Bet sizes allowed | 33%, 75%, all-in | `set_bet_sizes ...` |

A range is a set of `(combo → weight)` pairs; weight 0.25 = "defends this hand 25% of the
time preflop." **The abstraction:** the solver only considers the bet sizes you list (a 50%
bet literally does not exist in the tree if not declared); `set_use_isomorphism 1` collapses
suit-equivalent runouts. The solve is exact *only within the offered sizes/tree* — the #1
source of "solver says X but…": X is best *among the few options you gave it*.

---

## 2. The game tree: three node types

Postflop, **OOP acts first** on every street.

- **`action_node`** — a player chooses an action. Defined by `(whose turn, betting history,
  board)` — NOT the opponent's cards. The player holds a whole **range**; the solver computes
  a separate strategy for *every hand in it*.
- **`chance_node`** — a card is dealt. After a street closes (check-through or bet-call), the
  game branches **~47 ways on the turn**, **~46 on the river** (one child per unseen card).
  **Board texture / volatility physically lives here.**
- **`showdown_node` / `terminal_node`** — leaf. Fold → non-folder wins the pot; showdown →
  better hand wins, tie splits.

Flop subtree sketch (OOP first):
```
FLOP (pot 20)
└─ OOP: check | bet 33% | bet 75%
   ├─ OOP check → IP: check → TURN(chance) | bet 33% | bet 75%
   │                          └─ IP bet → OOP: fold | call → TURN | raise → ...
   └─ OOP bet → IP: fold | call → TURN | raise → ...
```

---

## 3. Counterfactual value (CFV) — the evaluation engine

At any node, for one hero hand, CFV = chips expected from this node onward, **weighted by how
often the opponent's range actually arrives here**.

Two ideas:

**Reach probability.** Each hand carries reach = product of the action-frequencies it took to
get here. The range at every node = start range **reweighted by strategy** → hands that never
take a line fade to ~0; the range narrows automatically (see §7).

**Counterfactual weighting** — weight by the *opponent's* reach, not hero's own:
```
CFV(I) = Σ over (villain combos v, future chance outcomes)
            π_villain(reach to I) × utility(hero hand vs v, under both strategies)
```
"Given I'm here with this hand, vs the slice of villain's range also here, what's my payoff?"

At a **showdown** leaf, utility is pure equity:
```
CFV = Σ_v P(v) × [ +pot if hero beats v | +pot/2 tie | 0 lose ] − chips invested
```
TexasSolver computes this by sorting both ranges by strength and sweeping — the same job
`lib/equity/evaluator.dart` does, vectorized over the whole range at once.

---

## 4. How "optimal" is decided: CFR / regret matching

**Optimal = Nash equilibrium**: neither player can raise EV by unilaterally deviating →
**unexploitable** (maximizes EV vs a worst-case opponent). NOT maximally exploitative vs a
specific villain (that's nodelocking). For heads-up zero-sum, a Nash equilibrium exists and
CFR converges to it.

**Per iteration, at every node, every hand:**
1. Compute `CFV(I, a)` for each action `a`.
2. `CFV(I)` = strategy-weighted average over actions.
3. `regret(I,a) = CFV(I,a) − CFV(I)`; accumulate `R(I,a) += regret`.
4. **Regret matching:** next strategy ∝ positive cumulative regret:
   `σ(I,a) = R⁺(I,a) / Σ R⁺(I,a')` (uniform if all ≤ 0).

Do it for **both players** every iteration — strategies co-evolve. Bluffs that get punished
accumulate negative regret and fade; +EV value bets grow. Regrets → 0 = equilibrium.

**Two subtleties:**
- **Take the *average* strategy, not the final one.** The per-iteration strategy oscillates
  around the equilibrium; the time-average converges and is what gets dumped.
- TexasSolver uses **Discounted CFR (DCFR)** — down-weights early ignorant iterations
  (positive regrets ∝ `t^1.5/(t^1.5+1)`, strategy ∝ `(t/(t+1))²`) → converges in ~150–200
  iters, not millions.

### Worked example — half-pot river, watch it converge

Pot $10. Hero OOP, polarized (equal value+air); value always bets. Decisions: hero-air
**Bet $5 / Check**; villain **Call $5 / Fold**. Known equilibrium: half-pot lays 5-to-15 →
value:bluff 3:1 → **hero bluffs air b\*=1/3**; hero indifferent → **villain calls c\*=2/3**.

Action values (change each iteration as opponent adapts):
- `v_air(Bet) = 10 − 15c` ; `v_air(Check) = 0`
- `v_vil(Call) = −5 + 20·b/(1+b)` ; `v_vil(Fold) = 0`

**Hero-air node**, starting uniform:

| Iter | villain c | v(Bet)=10−15c | σ(Bet)=b | strat-val | r(Bet) | r(Check) | cumR(Bet) | cumR(Check) | → next b |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.50 | +2.5 | 0.50 | 1.25 | +1.25 | −1.25 | +1.25 | −1.25 | **1.00** |
| 2 | 1.00 | −5.0 | 1.00 | −5.0 | 0 | +5.0 | +1.25 | +3.75 | **0.25** |
| 3 | 1.00 | −5.0 | 0.25 | −1.25 | −3.75 | +1.25 | −2.50 | +5.00 | **0.00** |
| 4 | 1.00 | −5.0 | 0.00 | 0 | −5.0 | 0 | −7.50 | +5.00 | **0.00** |

**Villain node:**

| Iter | hero b | P(air\|bet) | v(Call)=−5+20P | σ(Call)=c | strat-val | r(Call) | r(Fold) | cumR(Call) | cumR(Fold) | → next c |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.50 | 0.333 | +1.67 | 0.50 | 0.83 | +0.83 | −0.83 | +0.83 | −0.83 | **1.00** |
| 2 | 1.00 | 0.500 | +5.00 | 1.00 | 5.00 | 0 | −5.0 | +0.83 | −5.83 | **1.00** |
| 3 | 0.25 | 0.200 | −1.00 | 1.00 | −1.0 | 0 | +1.0 | +0.83 | −4.83 | **1.00** |
| 4 | 0.00 | 0.000 | −5.00 | 1.00 | −5.0 | 0 | +5.0 | +0.83 | +0.17 | **0.83** |

**The answer is the running average**, which trends to equilibrium even while the current
strategy oscillates wildly:

| | avg over iters 1–4 | target |
|---|---|---|
| hero bluff-air | (0.5+1.0+0.25+0)/4 = **0.44** | 1/3 ≈ 0.33 |
| villain call | (0.5+1.0+1.0+1.0)/4 = **0.875** | 2/3 ≈ 0.67 |

150+ iters lock onto (0.33, 0.67). That *is* "how optimal strategy is decided" — no oracle,
just accumulated regret + averaging. (Proper averaging is reach-weighted; simple mean shown
for hand-clarity.)

---

## 5. Exploitability — the convergence gate

After each batch, the solver computes **exploitability** = how much a perfect best-response
could win above the game value, vs the current average strategy, as **% of pot**. 0 at
equilibrium. Stop at a tolerance: the bridge uses `set_accuracy 0.5` → 0.5% of pot. The
`Total exploitability X precent` stdout line (note TexasSolver's actual typo) is parsed in
`run_solver.dart` (`_parseExploitability`). POC runs stopped at ~3–4.5% — close enough that
residual error is below the noise of the range assumptions.

---

## 6. The dump JSON structure (turn-walker reference)

`dump_result` writes the solved tree as nested JSON. Field names below are the **real ones the
bridge parses** (`childrens`, `strategy.actions`, `strategy.strategy`, `ev`, `ev_passive`,
`player`, `node_type` — `run_solver.dart:230–252`); values illustrative.

```jsonc
{
  "node_type": "action_node",
  "player": 0,                              // 0 = OOP acts first on flop
  "strategy": {
    "actions": ["CHECK", "BET 6.6", "BET 15"],
    "strategy": {                           // per-combo freqs ALIGNED to actions[]
      "Ah Kh": [0.25, 0.30, 0.45],
      "9s 9c": [0.55, 0.20, 0.25]
    }
  },
  "ev":         { "Ah Kh": [3.1, 4.0, 5.2] },   // ← our patch (chips, per action)
  "ev_passive": { "Ah Kh": [3.1, 2.8, 0.0] },   // ← check/call-only = realization (EQR target)
  "childrens": {
    "CHECK": {
      "node_type": "action_node", "player": 1,  // IP acts
      "strategy": { "actions": ["CHECK","BET 6.6","BET 15"], "strategy": { } },
      "childrens": {
        "CHECK": {                          // flop checks through → street closes
          "node_type": "chance_node",       // ★ THE TURN — branches ~47 ways
          "deal_number": 1,
          "childrens": {
            "2c": { "node_type":"action_node", "player":0, "strategy": {},
                    "childrens": { "CHECK": { "node_type":"chance_node" /* river */ } } },
            "Kh": { },                       // ← each key is a turn CARD
            "...": "... 47 of these ..."
          }
        },
        "BET 6.6": { },
        "BET 15":  { }
      }
    }
  }
}
```

Node types: **action_node** (has `player` + `strategy` + our `ev`/`ev_passive`; children keyed
by action string), **chance_node** (no strategy; children keyed by card — turn ~47, river
~46), **showdown/terminal** (leaf).

### Turn-walker design (for board-volatility calibration)
Current bridge does `set_dump_rounds 1` → dump stops at flop (chance children absent). To read
turns:
1. `set_dump_rounds 2` in `_buildInput` → turn `action_node`s included.
2. Descend to the flop `chance_node`: follow a line that closes the flop, e.g.
   `childrens["CHECK"].childrens["CHECK"]` (checked through) or
   `childrens["BET 15"].childrens["CALL"]` (bet–call).
3. Iterate that node's `childrens` — keys are the 47 turn cards. Per card, read hero's turn
   strategy (sizing/aggression swing) + node range reach.
4. **Volatility = dispersion across the 47 children** (variance of hero equity; fraction of
   turns where the top GTO action flips check↔bet or jumps size).

**Integration insight:** hero's *equity* across the 47 turns is computable for FREE from
`lib/equity/` (enumerate turns, sim vs villain's flop-continuing range — no solver). The
solver's unique value is confirming equity-variance drives **strategy** variance (sizing /
protection). So the turn-walker's real job is reading the **strategy swing** to validate /
calibrate the cheap equity-variance metric — the same "heuristic → solver-calibrate" move EQR
used.

---

## 7. Range weights narrow numerically down a line

Each combo's weight = preflop freq × product of action-freqs taken. At each node: reweight by
strategy, renormalize. Example — BB on 9♥7♥2♠ facing IP's $15 bet into $20 (MDF = 20/35 = 57%):

**Flop → after the call (turn range):**

| Hand group | flop mass | continue freq | continue mass | flop share | **turn share** |
|---|---|---|---|---|---|
| Sets / two pair | 12 | 1.00 | 12.0 | 18.2% | **28.6%** ▲ |
| Overpairs | 9 | 0.95 | 8.55 | 13.6% | **20.4%** ▲ |
| Top pair | 9 | 0.85 | 7.65 | 13.6% | **18.2%** ▲ |
| Flush draws | 12 | 0.80 | 9.6 | 18.2% | **22.9%** ▲ |
| Gutshots/backdoors | 12 | 0.30 | 3.6 | 18.2% | **8.6%** ▼ |
| Air | 12 | 0.05 | 0.6 | 18.2% | **1.4%** ▼▼ |
| **Total** | **66** | | **42.0** (63.6%, > MDF) | | |

Air **collapses** 18% → 1.4% (folded); value+draws concentrate. That's quantitatively *why*
"villain bet → cap his air" holds, and by how much. Another street (brick turn, bet–call)
narrows further → river range is value-heavy → solver bluffs less / value-bets thinner into it.

This is exactly what `villain_range.dart` *approximates* (chart range widened/tightened by
reads, narrowed per street by action). The solver does it **exactly** via reach weights, no
chart abstraction. Calibrating against the solver measures how far our heuristic narrowing
drifts from the solver's exact narrowing.

---

## 8. How it all maps to TableLab

| Solver concept | TableLab counterpart |
|---|---|
| Showdown leaf equity | `lib/equity/` evaluator + Monte Carlo |
| Reach-weighted range narrowing (§7) | `villain_range.dart` per-street narrowing (heuristic approx) |
| `ev_passive` (check/call-only EV) | **EQR realized-equity target** (`decision_context.dart`) |
| Low-SPR commitment nodes | SPR / commitment FACT |
| Call/fold freq facing a bet | MDF FACT |
| Equity/strategy variance across the 47 turn children | **board-volatility** (current build) |
| Average strategy + exploitability | what `run_solver.dart` reads + the quality gate |

The solver is a **future premium backend for the same `[FACT —]` slot** the DCE fills cheaply
(see `launch/DECISION_CONTEXT_ENGINE.md` build-vs-buy). Today we use it **offline to calibrate**
the heuristics (EQR refit PR #29 was a 69-spot solver run); we do not ship it in the request
path.
