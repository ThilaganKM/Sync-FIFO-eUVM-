# eUVM Bug Hunt 2: Synchronous FIFO

Build a UVM testbench in **eUVM** (UVM in the D language) for a 64-entry synchronous FIFO, run it on **Verilator**, and track down the **hidden bugs** in the RTL, step by step, by following the real history of how this testbench was built.

This repo is a **walkthrough**. Every commit is a real step of the original work: writing the spec and the plan, bringing up the build, writing each UVM component (with its code review), finding each RTL bug from the logs, fixing it, and closing coverage. Milestones are marked with **git tags** (`step-01-…` to `step-22-…`), so you can jump to any stage, try the next step yourself, and then compare with what was done.

> A first activity in the same style, finding bugs in a *testbench*, is [Multi-Bit-Comparator (eUVM Bug Hunt)](https://github.com/ThilaganKM/Multi-Bit-Comparator). This one is about finding bugs in the *design*.

---

## Contents

- [What you'll learn](#what-youll-learn)
- [Before you start](#before-you-start)
- [How to use this repo](#how-to-use-this-repo)
- [The steps](#the-steps)
- [The bug hunts](#the-bug-hunts)
- [Final task: improve the coverage model](#final-task-improve-the-coverage-model)
- [Documents in this repo](#documents-in-this-repo)
- [Credits and license](#credits-and-license)

---

## What you'll learn

- Turning a spec into a **verification plan**: checks, scenarios, coverage, sign-off criteria.
- The eUVM/Verilator flow: Verilating the DUT, the D testbench top, virtual interfaces, the makefile.
- Every UVM component: item, sequences, sequencer, driver, monitor, agent, env, scoreboard (reference model), tests, functional coverage.
- Getting **timing** right in a cycle-based testbench (drive on one edge, sample on the other).
- **Debugging from the log first**: reading the first error, telling an RTL bug from a testbench bug, writing a bug report, confirming in the waveform.
- Directed vs constrained-random tests, multi-seed regressions, **functional vs code coverage**.

## Before you start

**Tools**

| Tool | Version used | Notes |
|---|---|---|
| eUVM | `1.0-beta61` | `ldc2` (the D compiler shipped with eUVM) must be on `PATH` |
| Verilator | `5.044` (eUVM build) | must support `--euvm` |
| Python | 3.8+ | for the log viewer `sim/logview.py` |
| Waveform viewer | VaporView (VS Code extension) or gtkwave | optional, for confirming bugs |

**Background:** Verilog, and the general idea of UVM (agents, sequences, scoreboards). No D experience is needed: the review log explains every D construct as it appears.

**The rule of the game:** treat the RTL (`rtl/sync_fifo.v`) as a **black box**. Verify it against `SPEC.md` only: don't read the RTL to look for bugs. The bugs must be found the way a verification engineer finds them, from test results.

## How to use this repo

> ⚠️ **Read this README on GitHub (or with `git show main:README.md`) while you work.** It exists only in the latest commit, so it disappears when you check out an older step.

**1. Clone and list the steps**

```bash
git clone https://github.com/ThilaganKM/Sync-FIFO-eUVM-.git
cd Sync-FIFO-eUVM-
git tag -l 'step-*'          # the 22 milestones, in order
```

**2. Work on your own branch, starting from a step**

```bash
git switch -c my-work step-05-top        # a new branch "my-work", starting at that step
```

`git switch -c <branch> <tag>` creates a branch at the tagged commit and moves you onto it. Your commits go on **your** branch, so the original history is never touched.

**3. Try the next step yourself, then compare**

Read the next row of [the steps](#the-steps), implement it on your branch, run it, then see how it was done:

```bash
git diff step-06-stimulus -- testbench/     # your testbench vs the next step's
git show step-06-stimulus:REVIEW_LOG.md     # the code review of that step: the mistakes and their fixes
```

`git diff <tag> -- <path>` compares your working files with the tagged version (only under `<path>`). `git show <tag>:<file>` prints a file as it was at that step, without checking anything out.

**4. Move on**

Either keep building on your own branch, or start fresh from the next step:

```bash
git add -A && git commit -m "my version of step 6"   # keep your attempt
git switch -c my-work-7 step-06-stimulus              # continue from the original step 6
```

**5. Build and run** (after every switch, rebuild from clean)

```bash
cd sim
make clean
make run                                    # build + run the default test
make run TEST=fifo_test.<TestClass>         # a specific test
```

The tools grow during the walkthrough. Use what exists at your step:

| From step | Available |
|---|---|
| 04 | `make`, `make run` (save a log yourself: `make run 2>&1 \| tee x.log`) |
| 08 | `make view LOG=x.log`: compact, colour-coded log |
| 13 | `make table LOG=x.log ARGS=--first-error`: one row per clock edge; `make summary`: PASS/FAIL per log |
| 16 | Logs are named automatically, `sim/logs/<Test>_s<seed>.log`; `make regress` runs every test |
| 20 | `make seeds TEST=…` (many random seeds), `make coverage` (functional coverage, holes) |
| 22 | `make codecov` (Verilator code coverage, annotated RTL) |

Setup and tool problems that came up along the way are answered in `FAQ.md`.

**Two modes**

- **Hunt mode** (recommended): at each step, try first and only then compare. **Don't run `git log`**, and don't read the commit messages or `SOLUTIONS.md` until you've tried: the commit messages after each hunt step name the bug. Also, the docs (`FAQ.md`, `REVIEW_LOG.md`) at a hunt step were written *during* that hunt, and can contain hints for it: read them after your attempt.
- **Read mode**: walk through the commits in order and read each step's review. Faster, but you won't find the bugs yourself.

## The steps

| Tag | What this step adds | Your task before looking at the next step |
|---|---|---|
| `step-01-spec` | `SPEC.md`: the FIFO's behaviour, the single source of truth | Read it fully. What happens on a read+write at empty? At full? |
| `step-02-plan` | `VERIFICATION_PLAN.md`: checks CHK-01..07, scenarios TS-01..11, coverage, sign-off | Draft your own plan from SPEC §9, then compare |
| `step-03-rtl` | `rtl/sync_fifo.v`: **the DUT, with hidden bugs** | Black box from here on: note the ports, nothing else |
| `step-04-build` | `sim/makefile`: Verilating the DUT, the eUVM build | Adapt a makefile for this DUT (`make verilator.stamp`) |
| `step-05-top` | Testbench top (`sync_fifo_tb.d`), virtual interface (`fifo_intf.d`) | How should the DUT clock, the driver and the monitor line up in time? (FAQ: timing scheme) |
| `step-06-stimulus` | Item, sequencer, smoke sequence, driver, agent, env, test (+ `TESTBENCH_GUIDE.md`) | Write them; get the smoke test running |
| `step-07-monitor` | Monitor: one sample per cycle, at the falling edge | Write it; read the DUT's behaviour from the `[MON]` lines |
| `step-08-logview` | `sim/logview.py`, `make view` | (tooling) |
| `step-09-scoreboard` | Scoreboard: queue reference model, CHK-01..07 | Design the per-edge algorithm first, then code it |
| `step-10-base-classes` | `FifoBaseSeq` helpers, `FifoBaseTest` | Refactor: one sequence + one 5-line test class per scenario |
| `step-11-hunt-ts02` | TS-02 fill and drain test | **🐞 Bug hunt 1**: run it |
| `step-12-fix1` | Fix 1 (+ `SOLUTIONS.md`, Bug 1) | Compare your bug report and fix |
| `step-13-table` | `make table`, `make summary` | (tooling) |
| `step-14-hunt-ts05-ts06` | TS-05 read when empty, TS-06 write when full | **🐞 Bug hunt 2** |
| `step-15-fix2` | Fix 2 | Compare |
| `step-16-hunt-ts08` | TS-08 simultaneous read+write; auto-named logs, `make regress` | **🐞 Bug hunt 3** |
| `step-17-fix3` | Fix 3 | Compare |
| `step-18-hunt-ts10` | TS-10 reset mid-traffic | **🐞 Bug hunt 4** |
| `step-19-fix4` | Fix 4 | Compare |
| `step-20-random-coverage` | TS-11 constrained random, functional coverage (38 bins), `make coverage` | Predict which bins will be hardest to hit, then check |
| `step-21-signoff` | Regression: all tests pass, 100 % functional coverage | Is 100 % the end? (FAQ) |
| `step-22-codecov` | Verilator code coverage, `make codecov` | Compare code coverage with functional coverage |

## The bug hunts

At each **🐞 hunt** step, a new test has just been added and the RTL **still has the bug**:

1. Build and run that step's new test(s). The scoreboard reports mismatches.
2. Find the **first** error (from step 13: `make table … ARGS=--first-error`). Later errors are usually consequences of the first.
3. Decide **RTL or testbench**: look up every expected value in `SPEC.md`. If the scoreboard agrees with the spec, the DUT is wrong.
4. Write a **bug report**: test and seed; what was observed (log times, values); what the spec expects (clause); the evidence.
5. Optionally confirm in the waveform (`sim/sync_fifo_tb.vcd`) at the time of the first error.
6. Optionally fix the RTL yourself, then rerun every test (a regression).
7. Compare with the next **fix** step: `git show step-12-fix1:SOLUTIONS.md`, and `git diff step-11-hunt-ts02 step-12-fix1 -- rtl/` for the fix.

`SOLUTIONS.md` records each bug the way it was really found, including the wrong first guesses and the questions asked along the way ("Student questions"). It's the most useful file to read **after** each hunt.

## Final task: improve the coverage model

At `step-21-signoff`, functional coverage is 100 %, and at step 22, so is code coverage. Coverage measures **the plan**, not the design: 100 % only means every situation that was *listed* happened. Your last task is to review the coverage model itself:

- Which scenarios in `VERIFICATION_PLAN.md` are **not measured by any bin**? (Hint: look at the tests that span two consecutive edges.)
- What about the **data**: is there a bin that would notice if a data bit never toggled?
- Which **combinations of events on the same edge** might matter but aren't covered?

For each gap: add bins to `testbench/fifo_coverage.d`, run the regression, see whether the existing tests hit them, and add stimulus for any new holes. There's no reference answer: compare your reasoning with the FAQ entries "Coverage is 100 %. Am I done?" and "How do I get code coverage…".

## Documents in this repo

| File | What it is | Spoilers? |
|---|---|---|
| `SPEC.md` | The FIFO specification | No |
| `VERIFICATION_PLAN.md` | Checks, scenarios, coverage, sign-off criteria | No |
| `TESTBENCH_GUIDE.md` | How to build the first components (step 6) | No |
| `FAQ.md` | Every tool, workflow and methodology question that came up | Mostly no (see the hunt-mode note above) |
| `REVIEW_LOG.md` | Every code review: the mistakes, why they matter, and the fixes | Testbench solutions, step by step |
| `SOLUTIONS.md` | Each RTL bug: evidence, analysis, root cause, fix, regression | **Yes** |

## Credits and license

Testbench written and debugged by **Thilagan KM**, as an upskilling project in eUVM and Verilator.
The specification and the verification plan were developed by the author with AI assistance. The RTL (with its planted bugs), the testbench top and interface, the scoreboard, the coverage collector, the log tools and most of the documentation were written with **AI assistance (Claude, Anthropic)**, which also reviewed every testbench file the author wrote (`REVIEW_LOG.md`).

Licensed under the [Apache License 2.0](LICENSE).
