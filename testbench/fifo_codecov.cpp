// Code coverage writer (C++ glue).
//
// Verilator's --coverage puts line/toggle counters into the C++ model, but the
// eUVM D bindings have no call to save them. This one function does: the D top
// (sync_fifo_tb.d) calls it after the simulation, with the file name from the
// +codecov=<file> plusarg. The model is created with `new Vsync_fifo()`, so its
// counters live in Verilator's default context.
#include "verilated.h"
#include "verilated_cov.h"

extern "C" void fifo_codecov_write(const char* filename) {
    Verilated::defaultContextp()->coveragep()->write(filename);
}
