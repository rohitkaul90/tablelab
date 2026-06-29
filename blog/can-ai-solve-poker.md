---
title: "Can AI Solve Poker? What LLMs Do vs. What Solvers Do"
description: "AI beat poker pros in 2019, but with CFR solvers, not language models. Here's what LLMs actually do for your game, what they can't, and how to spot hype."
coverImage: "TODO: generate hero (1200x630); concept 'Solvers compute. Models explain.' on dark felt/#111811 with the −16.0 bb/100 stat"
coverImageAlt: "A poker table split between a game-tree diagram and a chat bubble, illustrating solvers versus language models."
ogImage: "TODO: same as coverImage"
date: "2026-06-29"
lastUpdated: "2026-06-29"
author: "TableLab Team"
tags: ["poker AI", "GTO solver", "poker strategy", "AI poker coach"]
---

# Can AI Solve Poker? What LLMs Do vs. What Solvers Do

AI already beat the world's best poker players. It happened in 2017, then again in 2019, and it wasn't ChatGPT. The bot that pulled it off ran on a math algorithm, not a chatbot. That gap matters now more than ever, because your feed is full of "AI poker coaches," and most of them blur what the AI is actually doing.

So can AI solve poker? Yes, a specific kind of AI, in a specific way. The version selling you a monthly subscription is usually a different thing wearing the same word. Here's exactly what each does, where each helps your game, and how to tell the difference.

> **TL;DR:** AI beat the pros, but the breakthrough (Pluribus, 2019) ran on **counterfactual regret minimization**, not a language model. LLMs out of the box are highly exploitable: in a 2026 benchmark the best general model trailed a specialized poker agent by **−16.0 bb/100**. Solvers *compute* GTO; language models *explain* it. Confusing the two is the tell of a hype-led "AI coach." ([Science, "Superhuman AI for multiplayer poker," 2019](https://www.science.org/doi/10.1126/science.aay2400))

[IMAGE: dark poker table with chips and cards, wide hero; Unsplash "poker chips dark felt"]

## Can AI actually solve poker?

In 2019, an AI named Pluribus became the first bot to beat professionals at six-player no-limit hold'em, and it did it on counterfactual regret minimization (CFR), not a language model ([Science, "Superhuman AI for multiplayer poker," 2019](https://www.science.org/doi/10.1126/science.aay2400)). Two years earlier, Libratus beat four pros across 120,000 hands of heads-up no-limit ([Carnegie Mellon University, 2019](https://www.cmu.edu/news/stories/archives/2019/july/cmu-facebook-ai-beats-poker-pros.html)). The milestone is real. The method is the part people skip.

"Solving" here has a precise meaning. The bot approaches a Nash equilibrium: a strategy so balanced that no opponent can exploit it in the long run. CFR gets there by playing itself millions of times and slowly regretting its mistakes less.

What's wild is how lean it was. Pluribus mastered the game in eight days on a 64-core server with under 512 GB of RAM ([KDnuggets, "Remembering Pluribus," 2020](https://www.kdnuggets.com/2020/12/remembering-pluribus-facebook-master-difficult-poker-game.html)). No data center. No language model. Just self-play with Monte Carlo CFR, grinding toward equilibrium.

<figure role="img" aria-label="Timeline of poker AI milestones from 2017 to 2026" style="margin:2.5rem 0;padding:1.25rem;background:transparent">
  <svg viewBox="0 0 600 200" xmlns="http://www.w3.org/2000/svg" style="max-width:100%;height:auto">
    <line x1="40" y1="120" x2="560" y2="120" stroke="#4CAF50" stroke-width="2"/>
    <!-- 2017 -->
    <circle cx="90" cy="120" r="7" fill="#4CAF50"/>
    <text x="90" y="150" fill="#cfd8dc" font-size="13" text-anchor="middle">2017</text>
    <text x="90" y="95" fill="#eceff1" font-size="12" text-anchor="middle">Libratus</text>
    <text x="90" y="78" fill="#90a4ae" font-size="10" text-anchor="middle">heads-up (CFR)</text>
    <!-- 2019 -->
    <circle cx="235" cy="120" r="7" fill="#4CAF50"/>
    <text x="235" y="150" fill="#cfd8dc" font-size="13" text-anchor="middle">2019</text>
    <text x="235" y="95" fill="#eceff1" font-size="12" text-anchor="middle">Pluribus</text>
    <text x="235" y="78" fill="#90a4ae" font-size="10" text-anchor="middle">6-max (CFR)</text>
    <!-- 2023 -->
    <circle cx="400" cy="120" r="7" fill="#90a4ae"/>
    <text x="400" y="150" fill="#cfd8dc" font-size="13" text-anchor="middle">2023</text>
    <text x="400" y="95" fill="#eceff1" font-size="12" text-anchor="middle">GPT-4 study</text>
    <text x="400" y="78" fill="#90a4ae" font-size="10" text-anchor="middle">deviates from GTO</text>
    <!-- 2026 -->
    <circle cx="525" cy="120" r="7" fill="#90a4ae"/>
    <text x="525" y="150" fill="#cfd8dc" font-size="13" text-anchor="middle">2026</text>
    <text x="525" y="95" fill="#eceff1" font-size="12" text-anchor="middle">LLM benchmark</text>
    <text x="525" y="78" fill="#90a4ae" font-size="10" text-anchor="middle">LLMs lag specialists</text>
  </svg>
  <figcaption style="color:#90a4ae;font-size:0.85rem">Green = CFR solvers (superhuman). Grey = language models (still lagging). Sources: Science 2019; arXiv 2023–2026.</figcaption>
</figure>

## What is a solver, and what does "solving" a hand mean?

A solver runs CFR over a game tree and outputs a near-unexploitable strategy: exact frequencies, equities, and expected value for every action. PioSolver and TexasSolver are the names you'll hear. The key point is that those numbers are *computed*. They're deterministic, reproducible, and they don't change because the solver is in a mood.

When a coach says "GTO," this is what they mean: the solver's output, not a vibe. A solver will tell you to barrel this turn 63% of the time and check the rest, and it can show you the EV of each line down to fractions of a big blind.

According to the 2019 *Science* paper, both Libratus and Pluribus built their strategies with Monte Carlo CFR before refining them in real time ([Science, "Superhuman AI for multiplayer poker," 2019](https://www.science.org/doi/10.1126/science.aay2400)). That's the engine behind every legitimate "GTO" number you've ever seen. A solver computes; it doesn't guess.

Want the deeper mechanics? [INTERNAL-LINK: how a CFR solver works → B2 "What Is a Poker Solver? CFR, Equity, and EV Explained for Live Players"].

## Why a language model is not a solver

A language model predicts text. It does not run CFR, and it does not compute a Nash equilibrium, so asking ChatGPT to "play GTO" is asking the wrong tool. As early as 2023, one of the first empirical studies found GPT-4 deviating systematically from GTO play preflop ([arXiv, "Are ChatGPT and GPT-4 Good Poker Players?", 2023](https://arxiv.org/pdf/2308.12466)). The newer models are better, but better isn't solved.

The deeper problem is *how* they reason. In 2026, researchers found that LLMs lean on shallow heuristics instead of game-theoretic principles, misjudge core inputs like opponent range estimation, and fail to reach a Nash equilibrium ([arXiv, "How Far Are LLMs from Professional Poker Players?", 2026](https://arxiv.org/html/2602.00528v1)). Off equilibrium means exploitable.

> **Our read:** a model that doesn't think in ranges will always have a leak a thinking opponent can find. <!-- [UNIQUE INSIGHT] -->

How big is the gap? In a 2026 benchmark pitting general models against a specialized poker agent, the strongest general model still trailed the specialist by **−16.0 bb/100** ([PokerNews, "GTO Wizard AI Outperforms GPT-5 and Grok 4 in New Benchmark," 2026](https://www.pokernews.com/news/2026/04/gto-wizard-ai-outperforms-gpt-5-and-grok-4-in-new-benchmark-51020.htm)). At those stakes, that's not a rounding error. It's the difference between a crusher and a donator.

<figure role="img" aria-label="Win-rate gap versus a specialized poker agent, in big blinds per 100 hands" style="margin:2.5rem 0;padding:1.25rem;background:transparent">
  <svg viewBox="0 0 560 220" xmlns="http://www.w3.org/2000/svg" style="max-width:100%;height:auto">
    <text x="20" y="30" fill="#eceff1" font-size="14">Win rate vs. a specialized poker agent (bb/100)</text>
    <!-- baseline -->
    <line x1="200" y1="50" x2="200" y2="190" stroke="#455a64" stroke-width="1" stroke-dasharray="4 3"/>
    <text x="200" y="205" fill="#90a4ae" font-size="11" text-anchor="middle">0 (specialist baseline)</text>
    <!-- specialist bar (at 0) -->
    <rect x="200" y="70" width="6" height="34" fill="#4CAF50"/>
    <text x="215" y="92" fill="#eceff1" font-size="12">Specialized poker agent: 0.0</text>
    <!-- LLM bar (negative, extends left) -->
    <rect x="60" y="130" width="140" height="34" fill="#ef9a9a"/>
    <text x="215" y="152" fill="#eceff1" font-size="12">Best general LLM (GPT-5.3): −16.0</text>
  </svg>
  <figcaption style="color:#90a4ae;font-size:0.85rem">Source: PokerNews, "GTO Wizard AI Outperforms GPT-5 and Grok 4 in New Benchmark," 2026.</figcaption>
</figure>

## So what are language models actually good for in poker?

Plenty, once you stop asking them to be solvers. A language model is genuinely strong at two jobs: turning dense solver output into plain English, and reasoning through spots no solver tractably covers, like big multiway pots or deep ICM situations where building the full tree isn't realistic. The catch is one word: grounding.

Research backs the nuance. A 2026 paper showed that an LLM equipped with structured rules, and no solver or training, could reach the range of solver-based performance, but only when its reasoning was scaffolded properly ([arXiv, "PokerSkill," 2026](https://arxiv.org/html/2605.30094v1)). Ungrounded, it drifts. Grounded in real numbers, it explains them well.

Think of it like a coach who can read a solver report fluently and talk you through *why*, but who should never make up the report. When does that distinction actually bite? Every time a tool states a frequency it never computed.

Multiway is the honest frontier here. [INTERNAL-LINK: why multiway pots aren't solved → B3 "Why Multiway Pots Aren't 'Solved'"].

## Why "AI poker coach" marketing should make you skeptical

The category sells a blur. "AI" gets stretched to imply "it solves your hand," when often a language model is just narrating, and the confusion is the product, not a bug. Even the strongest names lean on it: a leading study tool brands its solver-backed engine "GTO Wizard AI," and a 2026 benchmark lined it up against GPT, Claude, Gemini, and Grok ([PokerNews, 2026](https://www.pokernews.com/news/2026/04/gto-wizard-ai-outperforms-gpt-5-and-grok-4-in-new-benchmark-51020.htm)). That naming muddies solver-versus-LLM for everyone, even when the underlying engine is legitimate.

So how do you tell help from hype? Ask any AI poker tool four questions:

1. **Does it run a real solver?** Or is a language model improvising the numbers?
2. **Does it ever state a GTO percentage it didn't compute?** If yes, that number is a guess.
3. **Is the AI's prose grounded in solver output, or free-floating?** Grounded prose cites the math it's built on.
4. **Does it admit when a spot is unsolved?** Honest tools flag heuristic reasoning instead of faking certainty.

> **Our take:** if a tool can't answer those four cleanly, it's selling you the word "AI," not the work behind it. <!-- [UNIQUE INSIGHT] -->

[IMAGE: a player studying a phone at a live table, skeptical expression; Pexels "poker player phone casino"]

## How an honest AI poker tool should be built

Put a wall between the two layers. The solver owns the numbers. The language model owns the words and the judgment calls solvers can't reach, and it never crosses the wall to invent a frequency. That separation isn't a feature detail. It's the whole basis for trusting the output.

We built TableLab this way on purpose. A real CFR solver (TexasSolver) produces every equity, EV, and frequency figure. The language model receives those figures as hard facts injected into its prompt, explains them in plain English, and reasons about the spots the solver can't tractably cover, but it's barred from stating a GTO number it wasn't handed. When a read is heuristic, the tool says so. <!-- [PERSONAL EXPERIENCE] -->

Here's the split in one table:

| | CFR solver | Language model |
|---|---|---|
| Runs counterfactual regret minimization | Yes | No |
| Computes exact GTO frequencies | Yes | No |
| Reasons about opponent ranges | Yes (by construction) | Not reliably ([arXiv, 2026](https://arxiv.org/html/2602.00528v1)) |
| Can invent a number that sounds right | No (it's computed) | Yes (the core risk) |
| Best at | the math: equity, EV, frequency | the words: explanation, multiway heuristics |

When both layers stay in their lane, you get a number you can trust and an explanation you can read. Cross the streams, and you get confident nonsense.

## What this means for your live game

Live poker is mostly the spots solvers handle worst: multiway pots, deep stacks, and decisions where a read matters as much as a range. That's exactly where an honest heuristic plus *your own tracked results* beats a confident-sounding paragraph from a chatbot. A solver can't tell you that this villain never barrels a blank turn. Your notes can.

So the realistic stack is simple: a solver for the math, a grounded model for the explanation, and your own data for the table you actually sit at. [INTERNAL-LINK: what GTO actually means for live poker → B-pillar "What 'GTO' Actually Means for Live Poker"].

That's the bet behind TableLab: keep the layers honest, show you which is which, and tie it back to the results you've logged. [INTERNAL-LINK: how TableLab's analysis works → tablelab.app/about].

## Frequently Asked Questions

### Can ChatGPT play GTO poker?

No. Out of the box, language models deviate systematically from GTO and are highly exploitable. They lean on shallow heuristics, misjudge opponent range estimation, and don't reach a Nash equilibrium ([arXiv, "How Far Are LLMs from Professional Poker Players?", 2026](https://arxiv.org/html/2602.00528v1)). They can explain GTO concepts well. They just don't compute the equilibrium.

### Has AI beaten professional poker players?

Yes. Libratus beat four pros at heads-up no-limit in 2017, and Pluribus beat pros at six-player no-limit in 2019, both using counterfactual regret minimization, not language models ([Science, "Superhuman AI for multiplayer poker," 2019](https://www.science.org/doi/10.1126/science.aay2400)).

### Is GTO Wizard AI a solver?

It's a specialized, solver-backed poker engine, not a general language model. In a 2026 benchmark it outperformed GPT, Claude, Gemini, and Grok at the table ([PokerNews, 2026](https://www.pokernews.com/news/2026/04/gto-wizard-ai-outperforms-gpt-5-and-grok-4-in-new-benchmark-51020.htm)). The "AI" branding just blurs the solver-versus-LLM line.

### Can an AI review my poker hand accurately?

Only if its numbers come from a real solver and its explanation stays grounded in them. An ungrounded language model will state confident, wrong frequencies. The −16.0 bb/100 gap shows how far off general models still are ([PokerNews, 2026](https://www.pokernews.com/news/2026/04/gto-wizard-ai-outperforms-gpt-5-and-grok-4-in-new-benchmark-51020.htm)).

### Do poker solvers use AI?

Yes, but a specific kind: counterfactual regret minimization, a self-play algorithm that's the backbone of Libratus and Pluribus ([Science, 2019](https://www.science.org/doi/10.1126/science.aay2400)). It's a different branch of AI from the large language models behind chatbots.

## The bottom line

- AI did solve poker, via **CFR solvers** (Libratus 2017, Pluribus 2019), not language models.
- **Solvers compute** GTO frequencies; **language models explain** them and reason where solving isn't tractable.
- Out of the box, LLMs are exploitable. The best general model still trails a specialist by **−16.0 bb/100**.
- The "AI poker coach" blur is the hype. Demand grounding, and use the four-question test on any tool, including ours.

The honest version isn't a chatbot that "solves" your hand. It's a solver doing the math, a grounded model doing the words, and a tool that tells you which is which. That's the line TableLab won't cross. [INTERNAL-LINK: see how the analysis works → tablelab.app/about].

---

### Sources

- Science, "Superhuman AI for multiplayer poker," retrieved 2026-06-29, https://www.science.org/doi/10.1126/science.aay2400
- Carnegie Mellon University, "Carnegie Mellon and Facebook AI Beats Professionals in Six-Player Poker," retrieved 2026-06-29, https://www.cmu.edu/news/stories/archives/2019/july/cmu-facebook-ai-beats-poker-pros.html
- KDnuggets, "Remembering Pluribus: The Techniques that Facebook Used to Master World's Most Difficult Poker Game," retrieved 2026-06-29, https://www.kdnuggets.com/2020/12/remembering-pluribus-facebook-master-difficult-poker-game.html
- arXiv, "Are ChatGPT and GPT-4 Good Poker Players?: A Pre-Flop Analysis," retrieved 2026-06-29, https://arxiv.org/pdf/2308.12466
- arXiv, "How Far Are LLMs from Professional Poker Players? Revisiting Game-Theoretic Reasoning with Agentic Tool Use," retrieved 2026-06-29, https://arxiv.org/html/2602.00528v1
- arXiv, "PokerSkill: LLMs Can Play Expert-Level Poker without Training or Solvers," retrieved 2026-06-29, https://arxiv.org/html/2605.30094v1
- PokerNews, "GTO Wizard AI Outperforms GPT-5 and Grok 4 in New Benchmark," retrieved 2026-06-29, https://www.pokernews.com/news/2026/04/gto-wizard-ai-outperforms-gpt-5-and-grok-4-in-new-benchmark-51020.htm
- arXiv, "PokerBench: Training Large Language Models to become Professional Poker Players," retrieved 2026-06-29, https://arxiv.org/abs/2501.08328
