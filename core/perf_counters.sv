// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 06.10.2017
// Description: Performance counters


module perf_counters
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type bp_resolve_t = logic,
    parameter type dcache_req_i_t = logic,
    parameter type dcache_req_o_t = logic,
    parameter type exception_t = logic,
    parameter type icache_dreq_t = logic,
    parameter type scoreboard_entry_t = logic,
    parameter int unsigned NumPorts = 3  // number of miss ports
) (
    input logic clk_i,
    input logic rst_ni,
    input logic debug_mode_i,  // debug mode
    // SRAM like interface
    input logic [11:0] addr_i,  // read/write address (up to ariane_pkg::MHPMCounterNum counters possible)
    input logic we_i,  // write enable
    input logic [CVA6Cfg.XLEN-1:0] data_i,  // data to write
    output logic [CVA6Cfg.XLEN-1:0] data_o,  // data to read
    // from commit stage
    input  scoreboard_entry_t [CVA6Cfg.NrCommitPorts-1:0] commit_instr_i,     // the instruction we want to commit
    input  logic [CVA6Cfg.NrCommitPorts-1:0]              commit_ack_i,       // acknowledge that we are indeed committing
    // from L1 caches
    input logic l1_icache_miss_i,
    input logic l1_dcache_miss_i,
    // from MMU
    input logic itlb_miss_i,
    input logic dtlb_miss_i,
    // from issue stage
    input logic sb_full_i,
    // from frontend
    input logic if_empty_i,
    // from PC Gen
    input exception_t ex_i,
    input logic eret_i,
    input bp_resolve_t resolved_branch_i,
    // for newly added events
    input exception_t branch_exceptions_i,  //Branch exceptions->execute unit-> branch_exception_o
    input icache_dreq_t l1_icache_access_i,
    input dcache_req_i_t [2:0] l1_dcache_access_i,
    input  logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0]miss_vld_bits_i,  //For Cache eviction (3ports-LOAD,STORE,PTW)
    input logic i_tlb_flush_i,
    input logic stall_issue_i,  //stall-read operands
    input logic [31:0] mcountinhibit_i
);

  typedef logic [11:0] csr_addr_t;

  logic [63:0] generic_counter_d[MHPMCounterNum:1];
  logic [63:0] generic_counter_q[MHPMCounterNum:1];

  //internal signal to keep track of exception
  logic read_access_exception, update_access_exception;

  logic events[MHPMCounterNum:1];
  //internal signal for  MUX select line input
  logic [4:0] mhpmevent_d[MHPMCounterNum:1];
  logic [4:0] mhpmevent_q[MHPMCounterNum:1];
  // internal signal to detect event on multiple commit ports
  logic [CVA6Cfg.NrCommitPorts-1:0] load_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] store_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] branch_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] call_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] return_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] int_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] fp_event;

  for (genvar gen_commit_port = 0; gen_commit_port < CVA6Cfg.NrCommitPorts; gen_commit_port++) begin : gen_commit_events
    assign load_event[gen_commit_port] = commit_ack_i[gen_commit_port] &
                                         (commit_instr_i[gen_commit_port].fu == LOAD);
    assign store_event[gen_commit_port] = commit_ack_i[gen_commit_port] &
                                          (commit_instr_i[gen_commit_port].fu == STORE);
    assign branch_event[gen_commit_port] = commit_ack_i[gen_commit_port] &
                                           (commit_instr_i[gen_commit_port].fu == CTRL_FLOW);
    assign call_event[gen_commit_port] = commit_ack_i[gen_commit_port] &
                                         (commit_instr_i[gen_commit_port].fu == CTRL_FLOW) &
                                         ((commit_instr_i[gen_commit_port].op == ADD) ||
                                          (commit_instr_i[gen_commit_port].op == JALR)) &
                                         ((commit_instr_i[gen_commit_port].rd == 'd1) ||
                                          (commit_instr_i[gen_commit_port].rd == 'd5));
    assign return_event[gen_commit_port] = commit_ack_i[gen_commit_port] &
                                           (commit_instr_i[gen_commit_port].op == JALR) &
                                           (commit_instr_i[gen_commit_port].rd == 'd0);
    assign int_event[gen_commit_port] = commit_ack_i[gen_commit_port] &
                                        ((commit_instr_i[gen_commit_port].fu == ALU) ||
                                         (commit_instr_i[gen_commit_port].fu == MULT));
    assign fp_event[gen_commit_port] = commit_ack_i[gen_commit_port] &
                                       ((commit_instr_i[gen_commit_port].fu == FPU) ||
                                        (commit_instr_i[gen_commit_port].fu == FPU_VEC));
  end

  for (genvar gen_counter_event = 1; gen_counter_event <= MHPMCounterNum; gen_counter_event++) begin : gen_event_mux
    always_comb begin
      unique case (mhpmevent_q[gen_counter_event])
        5'b00000: events[gen_counter_event] = 0;
        5'b00001: events[gen_counter_event] = l1_icache_miss_i;  // L1 I-Cache misses
        5'b00010: events[gen_counter_event] = l1_dcache_miss_i;  // L1 D-Cache misses
        5'b00011: events[gen_counter_event] = itlb_miss_i;  // ITLB misses
        5'b00100: events[gen_counter_event] = dtlb_miss_i;  // DTLB misses
        5'b00101: events[gen_counter_event] = |load_event;  // Load accesses
        5'b00110: events[gen_counter_event] = |store_event;  // Store accesses
        5'b00111: events[gen_counter_event] = ex_i.valid;  // Exceptions
        5'b01000: events[gen_counter_event] = eret_i;  // Exception handler returns
        5'b01001: events[gen_counter_event] = |branch_event;  // Branch instructions
        5'b01010: events[gen_counter_event] =
            resolved_branch_i.valid && resolved_branch_i.is_mispredict;
        5'b01011: events[gen_counter_event] = branch_exceptions_i.valid;
        5'b01100: events[gen_counter_event] = |call_event;  // Call
        5'b01101: events[gen_counter_event] = |return_event;  // Return
        5'b01110: events[gen_counter_event] = sb_full_i;  // MSB Full
        5'b01111: events[gen_counter_event] = if_empty_i;  // Instruction fetch Empty
        5'b10000: events[gen_counter_event] = l1_icache_access_i.req;
        5'b10001: events[gen_counter_event] = l1_dcache_access_i[0].data_req ||
            l1_dcache_access_i[1].data_req || l1_dcache_access_i[2].data_req;
        5'b10010: events[gen_counter_event] =
            (l1_dcache_miss_i && miss_vld_bits_i[0] == 8'hFF) ||
            (l1_dcache_miss_i && miss_vld_bits_i[1] == 8'hFF) ||
            (l1_dcache_miss_i && miss_vld_bits_i[2] == 8'hFF);
        5'b10011: events[gen_counter_event] = i_tlb_flush_i;
        5'b10100: events[gen_counter_event] = |int_event;
        5'b10101: events[gen_counter_event] = |fp_event;
        5'b10110: events[gen_counter_event] = stall_issue_i;
        default:  events[gen_counter_event] = 0;
      endcase
    end
  end

  for (genvar gen_counter_update = 1; gen_counter_update <= MHPMCounterNum; gen_counter_update++) begin : gen_counter_update_logic
    localparam int unsigned CounterOffset = gen_counter_update - 1;
    localparam csr_addr_t MhpmCounterAddr =
        csr_addr_t'(riscv::CSR_MHPM_COUNTER_3) + csr_addr_t'(CounterOffset);
    localparam csr_addr_t MhpmCounterHighAddr =
        csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H) + csr_addr_t'(CounterOffset);
    localparam csr_addr_t MhpmEventAddr =
        csr_addr_t'(riscv::CSR_MHPM_EVENT_3) + csr_addr_t'(CounterOffset);

    always_comb begin
      generic_counter_d[gen_counter_update] = generic_counter_q[gen_counter_update];
      mhpmevent_d[gen_counter_update] = mhpmevent_q[gen_counter_update];

      if ((!debug_mode_i) && (!we_i) && events[gen_counter_update] &&
          (!mcountinhibit_i[gen_counter_update+2])) begin
        generic_counter_d[gen_counter_update] = generic_counter_q[gen_counter_update] + 1'b1;
      end

      if (we_i) begin
        if (addr_i == MhpmCounterAddr) begin
          if (riscv::XLEN == 32) begin
            generic_counter_d[gen_counter_update][31:0] = data_i;
          end else begin
            generic_counter_d[gen_counter_update] = data_i;
          end
        end else if (addr_i == MhpmCounterHighAddr) begin
          if (riscv::XLEN == 32) begin
            generic_counter_d[gen_counter_update][63:32] = data_i;
          end
        end else if (addr_i == MhpmEventAddr) begin
          mhpmevent_d[gen_counter_update] = data_i;
        end
      end
    end
  end

  always_comb begin : generic_counter_read
    data_o = 'b0;
    read_access_exception = 1'b0;
    update_access_exception = 1'b0;

    //Read
    if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3)) && (addr_i < ( csr_addr_t'(riscv::CSR_MHPM_COUNTER_3) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3+1][31:0];
      end else begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3+1];
      end
    end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H)) && (addr_i < ( csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3H+1][63:32];
      end else begin
        read_access_exception = 1'b1;
      end
    end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_EVENT_3)) && (addr_i < (csr_addr_t'(riscv::CSR_MHPM_EVENT_3) + MHPMCounterNum)) ) begin
      data_o = mhpmevent_q[addr_i-riscv::CSR_MHPM_EVENT_3+1];
    end else if( (addr_i >= csr_addr_t'(riscv::CSR_HPM_COUNTER_3)) && (addr_i < (csr_addr_t'(riscv::CSR_HPM_COUNTER_3) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_HPM_COUNTER_3+1][31:0];
      end else begin
        data_o = generic_counter_q[addr_i-riscv::CSR_HPM_COUNTER_3+1];
      end
    end else if( (addr_i > csr_addr_t'(riscv::CSR_HPM_COUNTER_3H)) && (addr_i < (csr_addr_t'(riscv::CSR_HPM_COUNTER_3H) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3H+1][63:32];
      end else begin
        read_access_exception = 1'b1;
      end
    end

    //Write access exceptions
    if (we_i) begin
      if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3)) && (addr_i < (csr_addr_t'(riscv::CSR_MHPM_COUNTER_3) + MHPMCounterNum)) ) begin
        update_access_exception = 1'b0;
      end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H)) && (addr_i < (csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H) + MHPMCounterNum)) ) begin
        if (riscv::XLEN != 32) update_access_exception = 1'b1;
      end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_EVENT_3)) && (addr_i < csr_addr_t'(riscv::CSR_MHPM_EVENT_3) + MHPMCounterNum) ) begin
        update_access_exception = 1'b0;
      end
    end
  end

  //Registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      generic_counter_q <= '{default: 0};
      mhpmevent_q       <= '{default: 0};
    end else begin
      generic_counter_q <= generic_counter_d;
      mhpmevent_q       <= mhpmevent_d;
    end
  end

endmodule
