/* Test bench for stage memory initialization
 *
 * This test bench is implemented here in C/C++.
 *
 * Copyright 2021 Leon Woestenberg <leon@brightai.com>. All rights reserved.
 */

#include <stdlib.h>

#include "Vsbp_lookup.h"

#include "verilated.h"
#include "verilated_vcd_c.h"

//#include "common.cpp"

#define VCD 1

int main(int argc, char **argv)
{
  // Initialize Verilators variables
  Verilated::commandArgs(argc, argv);

  // Create an instance of our module under test
  Vsbp_lookup *tb = new Vsbp_lookup;

  // init trace dump
  Verilated::traceEverOn(true);
  // init VCD
  VerilatedVcdC *tfp = new VerilatedVcdC;
  tb->trace(tfp, 99);
#if defined(VCD) && VCD
  // generates GByte files, disabled by default to prevent SSD wear
  tfp->open("sbp_lookup_tb.vcd");
#endif

  int test_result = 0;
  int timestamp = 0;

/*
   VL_IN8(clk,0,0);
    VL_IN8(rst,0,0);
    VL_IN(ip_addr_i,31,0);
    VL_OUT(result_o,16,0)
*/

  tb->clk = 0;
  tb->rst = 0;
  tb->eval();
  tb->ip_addr_i = 0xC0A80000;
  // Tick the clock until we are done
  //	while(!Verilated::gotFinish()) {
  //for (int t = 0; t < (n * x_range); t++)
  int count = 10;
  while(timestamp < 10)
  {
    tb->clk = 0;
    tb->eval();
    tb->clk = 1;
    tb->eval();
    tfp->dump(timestamp++);
  }
  tfp->close();
  printf("%s: %s\n", argv[0], test_result?"FAILED":"PASSED");
  exit(test_result);
}
