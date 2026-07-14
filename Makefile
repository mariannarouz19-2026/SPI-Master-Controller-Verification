# =============================================================================
# Makefile — SPI Master Verification Project
# Grading Interface Rev 1.2 compliant
# =============================================================================

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
PYTHON = python
RESULTS_DIR = parallel_results

# ---------------------------------------------------------------------------
# Simulator
# ---------------------------------------------------------------------------
VLIB   = vlib
VMAP   = vmap
VLOG   = vlog
VSIM   = vsim
VCOVER = vcover

VSIM_FLAGS = \
	-c \
	-coverage \
	-assertdebug \
	-voptargs=+acc
# ---------------------------------------------------------------------------
# User options
# ---------------------------------------------------------------------------
TEST             ?= sanity_test
SEED             ?= 1
WAVES            ?= 0
REGRESSION_SEEDS ?= 1

# ---------------------------------------------------------------------------
# DUT sources
# ---------------------------------------------------------------------------
GOLDEN_RTL ?= ./golden_rtl

DUT_SRCS ?= \
	$(GOLDEN_RTL)/spi_core.sv \
	$(GOLDEN_RTL)/apb_regfile.sv \
	$(GOLDEN_RTL)/spi_master.sv

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
HARNESS ?= ./harness

HARNESS_IF_SRCS = \
	$(HARNESS)/apb_if.sv \
	$(HARNESS)/spi_if.sv

HARNESS_WRAP_SRCS = \
	$(HARNESS)/dut_wrapper.sv

# ---------------------------------------------------------------------------
# TB Sources
# ---------------------------------------------------------------------------
TB_SRCS = \
	env/ref_model.sv \
	env/coverage.sv \
	sequences/stim_lib.sv \
	assertions/spi_sva.sv \
	tb/apb_master_bfm.sv \
	tb/spi_slave_bfm.sv \
	tests/sanity_test.sv \
	tests/width_coverage_test.sv \
	tests/loopback_test.sv \
	tests/mode_coverage_test.sv \
	tests/clk_div_corner_test.sv \
	tests/fifo_stress_test.sv \
	tests/interrupt_test.sv \
	tests/reg_access_test.sv \
	tests/error_injection_test.sv \
	tests/delay_transfer_test.sv \
	tb/tb_top.sv

# ---------------------------------------------------------------------------
# Compile flags
# ---------------------------------------------------------------------------
VLOG_COMMON_FLAGS = \
	-sv \
	-timescale=1ns/1ps \
	+acc=rn \
	+define+SIM

# Code coverage is applied only to DUT RTL.
DUT_COV_FLAGS = \
	+cover=bcestf

INCDIRS = \
	+incdir+. \
	+incdir+./tb \
	+incdir+./env \
	+incdir+./sequences \
	+incdir+./tests \
	+incdir+./assertions \
	+incdir+$(HARNESS)

# ---------------------------------------------------------------------------
# Regression tests
# ---------------------------------------------------------------------------
REGRESSION_TESTS = \
	sanity_test \
	loopback_test \
	width_coverage_test \
	mode_coverage_test \
	clk_div_corner_test \
	fifo_stress_test \
	interrupt_test \
	reg_access_test \
	error_injection_test \
	delay_transfer_test

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
.PHONY: compile run regress run_bonus cov clean help

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
compile:
	$(VLIB) work
	$(VMAP) work work

	@echo "[INFO] Compiling interfaces without code coverage..."
	$(VLOG) $(VLOG_COMMON_FLAGS) $(INCDIRS) \
		$(HARNESS_IF_SRCS)

	@echo "[INFO] Compiling DUT RTL with code coverage..."
	$(VLOG) $(VLOG_COMMON_FLAGS) $(DUT_COV_FLAGS) $(INCDIRS) \
		$(DUT_SRCS)

	@echo "[INFO] Compiling wrapper and testbench without code coverage..."
	$(VLOG) $(VLOG_COMMON_FLAGS) $(INCDIRS) \
		$(HARNESS_WRAP_SRCS) \
		$(TB_SRCS)

# ---------------------------------------------------------------------------
# Run single test
# ---------------------------------------------------------------------------
run:
	$(VSIM) $(VSIM_FLAGS) work.tb_top \
		+TESTNAME=$(TEST) +UVM_TESTNAME=$(TEST) +SEED=$(SEED) \
		$(if $(filter 1,$(WAVES)),-wlf waves_$(TEST)_$(SEED).wlf,) \
		-do "log -r /*; run -all; coverage save cov_$(TEST)_$(SEED).ucdb; quit -f"

# ---------------------------------------------------------------------------
# Regression
# ---------------------------------------------------------------------------
regress: compile
	@mkdir -p build
	$(PYTHON) run_parallel.py \
		--seeds $(REGRESSION_SEEDS) \
		--jobs 5 \
		--no-compile \
		--dut-srcs $(DUT_SRCS)
	@echo "[INFO] Regression complete"


# ---------------------------------------------------------------------------
# Bonus
# ---------------------------------------------------------------------------
run_bonus: compile
	$(VSIM) $(VSIM_FLAGS) work.tb_top \
		+TESTNAME=ral_hw_reset_test \
		+UVM_TESTNAME=ral_hw_reset_test \
		+SEED=$(SEED) \
		-do "run -all; quit -f"

# ---------------------------------------------------------------------------
# Coverage
# ---------------------------------------------------------------------------
cov:
	@mkdir -p build
	@if ls cov_*.ucdb > /dev/null 2>&1; then \
		$(VCOVER) merge build/merged.ucdb cov_*.ucdb; \
		$(VCOVER) report -details build/merged.ucdb > coverage_report.txt; \
		FUNC_COV=$$(awk '/TOTAL COVERGROUP COVERAGE:/ {val=$$4} END {print val}' coverage_report.txt); \
		TOTAL_COV=$$(awk '/Total Coverage By Instance \(filtered view\):/ {val=$$7} END {print val}' coverage_report.txt); \
		if [ -z "$$FUNC_COV" ]; then FUNC_COV="0.00%"; fi; \
		if [ -z "$$TOTAL_COV" ]; then TOTAL_COV="0.00%"; fi; \
		echo "" >> coverage_report.txt; \
		echo "================ GRADER COVERAGE SUMMARY ================" >> coverage_report.txt; \
		echo "Functional Coverage: $$FUNC_COV" >> coverage_report.txt; \
		echo "Total Coverage: $$TOTAL_COV" >> coverage_report.txt; \
		echo "Code Coverage: See DUT statement/branch coverage sections above." >> coverage_report.txt; \
		echo "=========================================================" >> coverage_report.txt; \
		echo ""; \
		echo "=== Coverage Summary ==="; \
		echo "Functional Coverage: $$FUNC_COV"; \
		echo "Total Coverage: $$TOTAL_COV"; \
		echo "Code Coverage: See DUT statement/branch coverage sections above."; \
		echo ""; \
		echo "coverage_report.txt written"; \
	else \
		echo "[ERROR] No cov_*.ucdb files found."; \
		exit 1; \
	fi

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	rm -rf work build transcript vsim.wlf *.wlf *.ucdb \
		coverage_report.txt *.log parallel_results \
	rm -rf work/ transcript *.wlf *.vcd *.fsdb

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help:
	@echo ""
	@echo "SPI Master Verification — available targets:"
	@echo "  make compile"
	@echo "  make run TEST=sanity_test SEED=1"
	@echo "  make regress"
	@echo "  make cov"
	@echo "  make clean"
	@echo ""
