//====================================================================
// File name   : tb_simulator_smoke.sv
// Author      : Project team with Codex
// Create date : 2026-11-03
// Description : Check that XSim advances time and evaluates assertions.
// Target      : FPGA
// Revision    : V1.0
//====================================================================
`timescale 1ns/1ps
module tb_simulator_smoke;
    reg clk = 1'b0;
    integer edges = 0;

    always #5 clk = ~clk;
    always @(posedge clk) edges = edges + 1;

    initial begin
        #101;
        if (edges !== 10) $fatal(1, "SIMULATOR_SMOKE_FAIL");
        $display("SIMULATOR_SMOKE_PASS");
        $finish;
    end
endmodule
