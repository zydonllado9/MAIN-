---
name: court
description: Put an idea on trial. A prosecutor argues against it, a defense attorney argues for it, 12 Claude jurors with distinct roles cast secret ballots, and a judge reads the ballots and hands down a verdict. Use when the user says "court", "put this on trial", "judge my idea", "be brutally honest", or wants a real stress test of a startup, product, feature, plan, or decision instead of agreement.
argument-hint: "<the idea to put on trial>"
---

# Claude Court

Claude tends to say yes to everything. This skill replaces one agreeable opinion with an adversarial trial: both sides argued in full, 12 independent jurors voting in secret, and a judge who reports the result as it is.

**Verdict language:** the idea is the defendant.
- **NOT GUILTY** means the idea holds up and is worth pursuing.
- **GUILTY** means the idea fails as stated and should not be pursued without major changes.

## Rules of the court (apply to every role)

- No hedging. Every juror must pick a side; "it depends" is not a ballot.
- No flattery. Do not praise the user or the idea's ambition. Judge the idea only.
- Be concrete. Every claim names a specific customer, number, competitor, cost, mechanism, or failure mode. Avoid generic risks like "execution risk" or "competition".
- The judge never overrides the jury's tally and never softens a GUILTY verdict.

## Procedure

### 1. File the case

Take the idea from the skill arguments or the conversation. If there is no idea at all, ask for one and stop. Otherwise do not ask clarifying questions: missing details are evidence too, and the trial should note them.

Write a short **Case File**:
- **The idea:** one or two sentences, restated neutrally.
- **Claims made:** what the user says it will achieve.
- **Unknowns:** important facts not given (target customer, pricing, distribution, cost, timeline).

Tell the user the court is in session, show the Case File, then continue without waiting.

### 2. Opening arguments: prosecution and defense

Run both attorneys **in parallel**. If you have a tool that spawns subagents (Agent/Task), launch two at once. Each one receives only the Case File and its own instructions, never the other side's brief. If you cannot spawn subagents, write each brief yourself in its own section, fully committing to that side.

**Prosecutor prompt:**
> You are the prosecutor in a trial of the following idea. Your only job is to make the strongest honest case that this idea will FAIL. Case File: <case file>. Write at most 250 words: the 3 most damaging charges, each with concrete evidence or reasoning (real competitors, unit economics, customer behaviour, technical or legal obstacles), then one sentence on the single fact that, if true, would sink the idea. Do not concede points and do not suggest fixes.

**Defense prompt:**
> You are the defense attorney in a trial of the following idea. Your only job is to make the strongest honest case that this idea will SUCCEED. Case File: <case file>. Write at most 250 words: the 3 strongest arguments, each with concrete evidence or reasoning (demand signals, timing, cost advantage, distribution, precedents), then one sentence on the single fact that, if true, would make the idea a clear win. Do not invent facts about the user; argue from what is plausible and known.

Show both briefs to the user under **Case For** and **Case Against**.

### 3. Jury deliberation: 12 secret ballots

Seat the 12 jurors listed in the roster below. Replace any juror who has no bearing on this idea with a better-fitting role (for example, a clinician for a health app or a teacher for an edtech tool), so the jury still has 12 distinct seats and keeps at least 4 natural skeptics.

The ballots are **secret and independent**. Launch all 12 jurors **in parallel** as subagents (in batches if your tool limits concurrency). Each juror receives the Case File, both briefs, their own role, and nothing about how anyone else voted. If you cannot spawn subagents, write each ballot one by one, staying fully in that juror's role, and decide each vote before looking at the others.

**Juror prompt:**
> You are Juror #<n>, <role>: <lens>. You are on a 12-person jury deciding whether this idea is GUILTY (it fails as stated and should not be pursued without major change) or NOT GUILTY (it holds up and is worth pursuing). Judge it only from your own perspective. Do not try to guess the majority, and do not be polite. Case File: <case file>. Case For: <defense brief>. Case Against: <prosecution brief>.
> Reply in exactly this format and nothing else:
> VERDICT: GUILTY or NOT GUILTY
> CONFIDENCE: 1-5
> REASON: one or two sentences from your role's perspective
> FLIP: the one specific fact or change that would make you vote the other way

### 4. The judge decides

Read all 12 ballots yourself and act as the judge. Count the votes exactly. A majority (7 or more) decides the verdict. A 6–6 split is a **HUNG JURY**: report it as such, along with the deciding question the jurors disagreed on.

Deliver the ruling in this format:

```
⚖️  THE PEOPLE v. <short idea name>

        GUILTY  <g>   |   NOT GUILTY  <n>

VERDICT: <GUILTY | NOT GUILTY | HUNG JURY> (<n>–<g>)
```

Then:

1. **The ballots:** a table with one row per juror: #, role, vote, confidence, reason (shortened).
2. **Judge's opinion:** 3–5 sentences on why the jury landed where it did, naming the argument that actually moved the votes. Weigh confidence: a 7–5 split carried by low-confidence votes is a weak verdict, and you should say so.
3. **The dissent:** the minority's strongest point, stated fairly.
4. **Conditions of release:** the 2–4 most common FLIP answers, phrased as the specific evidence or changes that would reverse or strengthen the verdict.
5. **Sentence:** next steps scaled to the verdict. For GUILTY, the cheapest test that could overturn it, or a stronger version of the idea. For NOT GUILTY, the riskiest assumption to test first and how. For HUNG JURY, the one experiment that would break the tie.

Keep the ruling under about 600 words, not counting the ballot table. End by offering a retrial if the user brings new evidence.

## Juror roster

| # | Role | Lens |
|---|------|------|
| 1 | Target customer | Would I actually pay for or switch to this, given what I use today? |
| 2 | Skeptical VC | Market size, defensibility, and whether this can return a fund. |
| 3 | Bootstrapped founder | Can one small team build, ship, and sell this profitably and soon? |
| 4 | Competitor's product lead | How fast could we copy this, and what would we do to kill it? |
| 5 | Growth marketer | How does anyone hear about it? What are the channel, CAC, and hook? |
| 6 | Engineer | What is hard, slow, or expensive to build and run that the pitch ignores? |
| 7 | CFO / accountant | Unit economics, burn, pricing, and payback. Do the numbers close? |
| 8 | Lawyer / regulator | Liability, compliance, IP, privacy, platform terms. |
| 9 | Devil's advocate | Attacks the most popular assumption, whichever side it supports. |
| 10 | Early adopter / enthusiast | Is there a real "wow" here that would make people evangelize it? |
| 11 | Industry veteran (20 years) | Has this been tried before? Why did it fail, and what is different now? |
| 12 | The user's future self, 2 years on | Was this the best use of those 2 years compared with the alternatives? |
