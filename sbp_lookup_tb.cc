/* Test bench for stage memory initialization
 *
 * This test bench is implemented here in C/C++.
 *
 * Copyright 2021 Leon Woestenberg <leon@brightai.com>. All rights reserved.
 */

#include <limits.h>
#include <stdlib.h>
#include <assert.h>

#include "Vsbp_lookup.h"

#include "verilated.h"
#include "verilated_vcd_c.h"

//#include "common.cpp"

#define VCD 1

#define LATENCY (65)
uint32_t ip_addr_i[LATENCY];
uint32_t ip_addr2_i[LATENCY];
int ip_addr_index = 0;

int read_prefix(FILE *fp, uint32_t *prefix_p, int *prefix_len_p)
{
  int result = -1;
  int numbers[4];
  int prefix_len = 0;
  int rc;
  uint32_t addr = 0;
  if ((prefix_p == NULL) || (prefix_len_p == NULL)) goto end;
  rc = fscanf(fp, "%d.%d.%d.%d/%d\n", &numbers[0], &numbers[1], &numbers[2], &numbers[3], &prefix_len);
  if (rc != 5) {
    perror("fscanf()");
    goto end;
  }
  for (int i = 0; i < 4; i++) {
    if ((numbers[i] < 0) || (numbers[i] >= 255)) goto end;
    addr <<= 8;
    addr |= numbers[i];
  }
  //printf("%d.%d.%d.%d/%d ", numbers[0], numbers[1], numbers[2], numbers[3], prefix_len);
  //printf("0x%08x\n", addr);
  *prefix_p = addr; 
  *prefix_len_p = prefix_len;
  result = 0;
end:
  return result;
}

int main(int argc, char **argv)
{
  FILE *fp;
  fp = fopen("../scalable-pipelined-lookup-c/frug.ipp", "r");
  if (fp == NULL) return -1;

  uint32_t prefix;
  int prefix_len;
  int rc;

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
  tb->ip_addr_i = 0x00000000u;
  tb->eval();
  // Tick the clock until we are done
  //	while(!Verilated::gotFinish()) {
  //for (int t = 0; t < (n * x_range); t++)
  int cycles = 0;

  while (cycles < 64*2)
  {
    // set inputs

    tb->ip_addr_i = 0;
    tb->ip_addr2_i = 0;
    tb->upd_ip_addr_i = 0;
    tb->upd_length_i = 0;
    tb->upd_stage_id_i = 0;
    tb->upd_location_i = 0;
    tb->upd_childs_stage_id_i = 0;
    tb->upd_childs_location_i = 0;
    tb->upd_childs_lr_i = 0;
    tb->upd_i = 0;
#if 0
    /* update cycle */
    if (cycles == 1) { 
      tb->upd_ip_addr_i = 0x327b23c0u;
      tb->upd_length_i = 24;
      /* entry to be written */
      tb->upd_stage_id_i = 3;
      tb->upd_location_i = 1;
      /* pointer to child */
      tb->upd_childs_stage_id_i = 0x3c;
      tb->upd_childs_location_i = 0x123;
      tb->upd_childs_lr_i = 0;
      tb->upd_i = 1;
    }
#endif
#if 1
    if (cycles == 3) {
      tb->lookup_i = 1;
      tb->ip_addr_i = ip_addr_i[ip_addr_index % LATENCY] = 0x7545e140u;
      tb->ip_addr2_i = ip_addr2_i[ip_addr_index % LATENCY] = 0x7545e140u;
    }
#endif    
#if 0
    else if (cycles == 6) {
      tb->lookup_i = 1;
      tb->ip_addr_i  = ip_addr_i [ip_addr_index % LATENCY] = 0x327b23f0u;
      tb->ip_addr2_i = ip_addr2_i[ip_addr_index % LATENCY] = 0x62555800u;
    }
#endif
#if 0
    else if (cycles > 4) {
      tb->lookup_i = 1;
      tb->ip_addr_i = ip_addr_i[ip_addr_index % LATENCY] = (rand() % UINT32_MAX);
    }
#endif
#if 0
    else if (cycles > 4) {
      rc = read_prefix(fp, &prefix, &prefix_len);
      tb->lookup_i = 1;
      tb->ip_addr_i = ip_addr_i[ip_addr_index % LATENCY] = prefix;
    }
#endif
    else {
      tb->lookup_i = 0;
    }
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
      printf("0x%08x -> 0x%08x, ", ip_addr_i [(ip_addr_index + LATENCY + 1) % LATENCY], tb->result_o);
      printf("0x%08x -> 0x%08x\n", ip_addr2_i[(ip_addr_index + LATENCY + 1) % LATENCY], tb->result2_o);
    }

    ip_addr_index += 1;
    cycles++;
  }
  tfp->close();
  printf("%s: %s\n", argv[0], test_result?"FAILED":"PASSED");

  if (fp != NULL ) fclose(fp);

  exit(test_result);
}
