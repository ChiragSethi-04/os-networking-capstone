SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

VENV := .venv
PY := $(VENV)/bin/python3

.PHONY: preflight venv lab test test-phase1 test-phase2 test-phase3 test-phase4 test-phase5 \
        bench bench-quick figures report report-check slides demo demo-reset \
        final-check clean

preflight:
	bash lab/scripts/preflight.sh

venv:
	python3 -m venv $(VENV)
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q matplotlib pandas numpy scipy python-pptx python-docx pillow flask gunicorn pymysql

lab:
	bash lab/scripts/provision.sh
	bash lab/scripts/deploy_site.sh
	bash lab/scripts/harden.sh

test: test-phase1 test-phase2 test-phase3 test-phase4 test-phase5

test-phase1:
	bash lab/scripts/test_phase1.sh

test-phase2:
	bash lab/scripts/test_phase2.sh

test-phase3:
	bash lab/scripts/test_phase3.sh

test-phase4:
	bash lab/scripts/test_phase4.sh

test-phase5:
	bash lab/scripts/test_phase5.sh

bench:
	bash experiments/run_all.sh

bench-quick:
	bash experiments/run_all.sh --quick

figures: venv
	$(PY) figures/figures.py

report:
	bash report/build_report.sh

report-check:
	bash report/check_report.sh

slides: venv
	$(PY) slides/build_deck.py

demo:
	bash lab/scripts/demo.sh

demo-reset:
	bash lab/scripts/demo_reset.sh

final-check:
	bash lab/scripts/final_check.sh

clean:
	rm -rf $(VENV) evidence/processed/*.csv figures/*.png
