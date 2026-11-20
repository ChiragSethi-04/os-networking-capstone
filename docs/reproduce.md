# Reproducing this project from scratch

```bash
# 0. One-time host setup (see CLAUDE_CODE_GUIDE.md Part A), then:
make preflight

# 1. Provision the lab (3 Multipass VMs, ~10-20 min depending on network)
make lab

# 2. Run every phase's acceptance check
make test

# 3. Run all nine experiments (full: 5 repeats; use `make bench-quick` for
#    a fast 2-repeat smoke test instead)
make bench

# 4. Generate every figure from the CSVs experiments just produced
make figures

# 5. Build the report (PDF + DOCX)
make report
make report-check

# 6. Build the slide deck
make slides

# 7. Final full rebuild + packaging (Phase 10)
make final-check
```

Every step writes its evidence to `evidence/raw/` (untouched tool output)
and `evidence/processed/` (parsed CSVs + notes) before the next step
reads it; nothing in `figures/` or `report/` is hand-edited input data,
only generated output.

To re-run a single phase instead of the whole pipeline, use the
individual Makefile targets (`make test-phase3`, `make bench`, etc.) - see
`Makefile` for the full target list, or `CLAUDE_CODE_GUIDE.md` Part C for
what each phase does.

`make demo-reset` restores all three VMs to their `clean-baseline`
snapshot and re-applies Phases 2-5, for a fresh state immediately before
presenting.
