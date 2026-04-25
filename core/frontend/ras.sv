//Copyright (C) 2018 to present,
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 08.02.2018
// Migrated: Luis Vitorio Cargnini, IEEE
// Date: 09.06.2018

// return address stack
module ras #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type ras_t = logic,
    parameter int unsigned DEPTH = 2
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Branch prediction flush request - zero
    input logic flush_bp_i,
    // Push address in RAS - FRONTEND
    input logic push_i,
    // Pop address from RAS - FRONTEND
    input logic pop_i,
    // Data to be pushed - FRONTEND
    input logic [CVA6Cfg.VLEN-1:0] data_i,
    // Popped data - FRONTEND
    output ras_t data_o
);

  ras_t [DEPTH-1:0] stack_d, stack_q;
  ras_t             push_entry;

  assign data_o = stack_q[0];
  assign push_entry.ra = data_i;
  assign push_entry.valid = 1'b1;

  if (DEPTH == 1) begin : gen_single_entry_stack
    assign stack_d[0] = flush_bp_i ? '0 :
                        push_i     ? push_entry :
                        pop_i      ? '0 :
                                     stack_q[0];
  end else begin : gen_multi_entry_stack
    for (genvar i = 0; i < DEPTH; i++) begin : gen_stack_d
      if (i == 0) begin : gen_top
        assign stack_d[i] = flush_bp_i ? '0 :
                            push_i     ? push_entry :
                            pop_i      ? stack_q[i+1] :
                                         stack_q[i];
      end else if (i == DEPTH - 1) begin : gen_bottom
        assign stack_d[i] = flush_bp_i       ? '0 :
                            (push_i & pop_i) ? stack_q[i] :
                            push_i           ? stack_q[i-1] :
                            pop_i            ? '0 :
                                               stack_q[i];
      end else begin : gen_middle
        assign stack_d[i] = flush_bp_i       ? '0 :
                            (push_i & pop_i) ? stack_q[i] :
                            push_i           ? stack_q[i-1] :
                            pop_i            ? stack_q[i+1] :
                                               stack_q[i];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      stack_q <= '0;
    end else begin
      stack_q <= stack_d;
    end
  end
endmodule
