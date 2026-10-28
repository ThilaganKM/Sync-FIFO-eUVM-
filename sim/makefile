# ---------------------------------------------------------------
# Project settings (the only lines to edit for another DUT)
# ---------------------------------------------------------------
DUT        = sync_fifo
TOP        = sync_fifo_tb
TEST      ?= fifo_test.FifoTest
SEED      ?= 1
VERBOSITY ?= UVM_HIGH

RTL_SRC = ../rtl/$(DUT).v
TB_SRC  = ../testbench/$(TOP).d \
          ../testbench/fifo_intf.d \
          ../testbench/fifo_item.d \
          ../testbench/fifo_sequencer.d \
          ../testbench/fifo_seq.d \
          ../testbench/fifo_driver.d \
          ../testbench/fifo_monitor.d \
          ../testbench/fifo_scoreboard.d \
          ../testbench/fifo_agent.d \
          ../testbench/fifo_env.d \
          ../testbench/fifo_test.d

# ---------------------------------------------------------------
# Tools
# ---------------------------------------------------------------
DFLAGS     = -relocation-model=pic -w -O3
LDC2BINDIR = $(dir $(shell which ldc2))
VLBINDIR   = $(dir $(shell which verilator))
VL_INC     = -I ../obj_dir/ -I $(VLBINDIR)/../share/verilator/include
ESDL_CPP   = $(LDC2BINDIR)/../import/esdl/intf/verilator/cpp

# Everything Verilator produces that the final link needs
VLATOR_OBJS = euvm_dir/V$(DUT)_euvm.d \
              euvm_dir/V$(DUT)_euvm_funcs.o \
              euvm_dir/verilated_vcd_d.o euvm_dir/verilated_d.o \
              obj_dir/V$(DUT)__ALL.a \
              obj_dir/verilated.o obj_dir/verilated_threads.o obj_dir/verilated_vcd_c.o

# ---------------------------------------------------------------
# Tests and logs
# ---------------------------------------------------------------
# Every test class in fifo_test.d. `make regress` runs them all.
TESTS = FifoTest FifoFillDrainTest FifoReadEmptyTest FifoWriteFullTest FifoWriteReadSimTest FifoResetTest

# Each run's log is named after its test and seed: logs/<Test>_s<seed>.log
# (fifo_test.FifoTest -> FifoTest), so a log name always says what produced it.
LOGDIR   = logs
TESTNAME = $(lastword $(subst ., ,$(TEST)))
RUNLOG   = $(LOGDIR)/$(TESTNAME)_s$(SEED).log

.PHONY: all run regress view table summary clean cleanlogs

# If a recipe fails, delete its target (e.g. verilator.stamp), so a failed
# step is never mistaken for a finished one on the next make.
.DELETE_ON_ERROR:

all: $(TOP)

# One test. Output goes to the terminal AND to $(RUNLOG).
#   make run TEST=fifo_test.FifoWriteReadSimTest SEED=7
# stdbuf -oL: line-buffer stdout. UVM messages go to stdout (block-buffered
# when piped, e.g. into tee) and ESDL kernel messages go to stderr (unbuffered);
# without this, the two streams interleave out of order in the terminal/log.
run: $(TOP)
	@mkdir -p $(LOGDIR)
	stdbuf -oL ./$(TOP) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) +seed=$(SEED) 2>&1 | tee $(RUNLOG)
	@echo "Log written to $(RUNLOG)"

# Every test in TESTS with the same SEED, then the summary table.
#   make regress            make regress SEED=7
regress: $(TOP)
	@for t in $(TESTS); do \
	    echo "running $$t (seed $(SEED)) -> $(LOGDIR)/$${t}_s$(SEED).log"; \
	    $(MAKE) --no-print-directory run TEST=fifo_test.$$t SEED=$(SEED) > /dev/null; \
	done
	@$(MAKE) --no-print-directory summary

# Views of a saved log (see logview.py). LOG defaults to the most recent log.
#   make view                                   stream view of the latest run
#   make table LOG=logs/FifoWriteFullTest_s1.log
#   make table ARGS=--first-error               (start here on a FAIL)
#   make table ARGS="--around 1300 --context 5"
LOG  ?= $(shell ls -t $(LOGDIR)/*.log 2>/dev/null | head -n 1)
ARGS ?=
view:
	python3 logview.py --color $(LOG) | less -R

table:
	python3 logview.py --color --table $(ARGS) $(LOG) | less -R

# Regression summary: one PASS/FAIL line per log in logs/.
summary:
	@python3 logview.py --color --summary $(sort $(wildcard $(LOGDIR)/*.log))

# Build products only. Logs are kept: delete them with `make cleanlogs`.
clean:
	rm -rf $(TOP) $(TOP).o *.vcd euvm_dir obj_dir verilator.stamp

cleanlogs:
	rm -rf $(LOGDIR)

# ---------------------------------------------------------------
# Step 1: Verilate the RTL and compile the C++ glue
# ---------------------------------------------------------------
# The stamp is touched FIRST, so every file generated below is newer than it.
# (.DELETE_ON_ERROR removes the stamp again if any step fails.)
verilator.stamp: $(RTL_SRC)
	touch verilator.stamp
	verilator --no-timing --threads 1 --trace --cc --euvm $^
	(cd euvm_dir; g++ -c $(VL_INC) V$(DUT)_euvm_funcs.cpp)
	(cd euvm_dir; g++ -c $(VL_INC) $(ESDL_CPP)/verilated_vcd_d.cpp -o verilated_vcd_d.o)
	(cd euvm_dir; g++ -c $(VL_INC) $(ESDL_CPP)/verilated_d.cpp -o verilated_d.o)
	$(MAKE) -C obj_dir -f V$(DUT).mk V$(DUT)__ALL.a verilated.o verilated_vcd_c.o verilated_threads.o

$(VLATOR_OBJS): verilator.stamp

# ---------------------------------------------------------------
# Step 2: compile the D testbench and link everything
# ---------------------------------------------------------------
$(TOP): $(TB_SRC) $(VLATOR_OBJS)
	ldc2 $(DFLAGS) -Ieuvm_dir -link-defaultlib-shared -of$@ \
		-L-luvm-ldc-shared -L-lesdl-ldc-shared -L-lz3 -L-lphobos2-ldc-shared -L-ldl \
		$^ -L-lstdc++
