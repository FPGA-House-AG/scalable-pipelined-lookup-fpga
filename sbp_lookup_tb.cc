/* Test bench for stage memory initialization
 *
 * This test bench is implemented here in C/C++.
 *
 * Copyright 2021 Leon Woestenberg <leon@brightai.com>. All rights reserved.
 */

#include <limits.h>
#include <stdlib.h>

#include "Vsbp_lookup.h"

#include "verilated.h"
#include "verilated_vcd_c.h"

//#include "common.cpp"

#define VCD 1

#define LATENCY (33)
uint32_t ip_addr_i[LATENCY];
int ip_addr_index = 0;

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
  tb->ip_addr_i = 0x00000000u;
  // Tick the clock until we are done
  //	while(!Verilated::gotFinish()) {
  //for (int t = 0; t < (n * x_range); t++)
  int cycles = 0;

  while (cycles < 64)
  {
    // set inputs
    if (cycles == 1) { 
      tb->ip_addr_i = 0x327b23c0u;
      tb->upd_length_i = 24;
      /* entry to be written */
      tb->upd_stage_id_i = 3;
      tb->upd_location_i = 1;
      /* pointer to child */
      tb->upd_childs_stage_id_i = 0x3c;
      tb->upd_childs_location_i = 0x123;
      tb->upd_childs_lr_i = 0;
      tb->upd_i = 1;
    } else {
      tb->ip_addr_i = 0;
      tb->upd_length_i = 0;
      tb->upd_stage_id_i = 0;
      tb->upd_location_i = 0;
      tb->upd_childs_stage_id_i = 0;
      tb->upd_childs_location_i = 0;
      tb->upd_childs_lr_i = 0;
      tb->upd_i = 0;
    }

    if (cycles == 3)
      tb->ip_addr_i = ip_addr_i[ip_addr_index % LATENCY] = 0x7545e140u;
    else if (cycles == 4)
      tb->ip_addr_i = ip_addr_i[ip_addr_index % LATENCY] = 0x327b23f0u;
#if 0
    else if (cycles > 4)
      tb->ip_addr_i = ip_addr_i[ip_addr_index % LATENCY] = (rand() % UINT32_MAX);
#endif
    // falling edge
    tb->clk = 0;
    tb->eval();
    tfp->dump(timestamp++);

    // rising edge
    tb->clk = 1;
    tb->eval();
    tfp->dump(timestamp++);
    
    // check outputs
    if (cycles >= LATENCY) {
      printf("0x%08x -> 0x%08x\n", ip_addr_i[(ip_addr_index + LATENCY + 1) % LATENCY], tb->result_o);
    }

    ip_addr_index += 1;
    cycles++;
  }
  tfp->close();
  printf("%s: %s\n", argv[0], test_result?"FAILED":"PASSED");
  exit(test_result);
}
