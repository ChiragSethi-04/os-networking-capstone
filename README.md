# OS & Networking Capstone — Deploying a Secure Web Server & Hosting a Company Website

Group 6: Chirag Sethi, Shree Iyengar, Hardik Sharma, Mehul Nagarkoti

A reproducible lab that provisions a 3-VM environment (web / database / attacker) on
Multipass, deploys and hardens a company website behind Nginx with TLS, sets up
monitoring and log rotation, then runs a set of benchmark and security experiments
(performance under load, TLS grading, brute-force/Fail2Ban response, packet-capture
proof of encryption, and failure/resilience recovery) to produce the data behind the
accompanying report, figures, and slide deck.

## Layout

- `lab/` — cloud-init configs and scripts to provision, deploy, and harden the VMs
  (`provision.sh`, `harden.sh`, `setup_monitoring.sh`, `demo.sh`)
- `experiments/` — `run_E1.sh` … `run_E9.sh` benchmark/security experiments plus their
  Python parsers, driven by `run_all.sh`
- `evidence/` — raw experiment output (`raw/`) and parsed CSV/markdown summaries
  (`processed/`)
- `figures/` — `figures.py` generates report charts from `evidence/processed/*.csv`
- `report/` — the written report (`report.md`) and its build/check scripts
- `slides/` — slide deck builder
- `site/` — the company website deployed to the web VM
- `docs/` — decision log, rubric self-audit, demo script, viva Q&A, peer review docs

## Running it

```
make preflight   # check local tooling
make lab         # provision + deploy + harden + monitor
make test        # phase verification checks
make bench-quick # run all experiments (quick mode)
make figures      # build charts from evidence
make report-check
make slides
```

See `docs/decisions.md` for the detailed log of issues hit during provisioning,
hardening, and experiment runs, and why each fix was made.
