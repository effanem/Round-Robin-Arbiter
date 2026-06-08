FILES = ../rtl/round_robin.sv ../tb/rr_interface.sv ../tb/rr_pkg.sv ../tb/rr_tb_top.sv

TOPLEVEL = rr_tb_top

# Change these to switch arbiter type and size
N    = 10
W    = 3
TYPE = 2

DEFINES = +define+N=$(N)+W=$(W)+TYPE=$(TYPE)

help:
	@echo "Make targets:"
	@echo "> make questa_gui  # Compile and run with Questa in GUI mode"
	@echo "> make questa_cmd  # Compile and run with Questa in command mode"
	@echo "> make clean       # Clean up all intermediate files"
	@echo "> make help        # This message"

questa_gui:
	vlib work
	vmap work work
	vlog $(DEFINES) $(FILES)
	vsim -novopt -do "view wave;add wave -radix hex -r *;run -all" $(TOPLEVEL)

questa_cmd:
	vlib work
	vmap work work
	vlog $(DEFINES) $(FILES)
	vsim -c -novopt -do "run -all" $(TOPLEVEL)

clean:
	@rm -rf work vsim.wlf transcript modelsim.ini *.vcd *.log
