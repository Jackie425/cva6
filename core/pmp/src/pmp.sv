// Copyright 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Moritz Schneider, ETH Zurich
// Date: 2.10.2019
// Description: purely combinatorial PMP unit (with extraction for more complex configs such as NAPOT)

module pmp
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty
) (
    // Input
    input logic [CVA6Cfg.PLEN-1:0] addr_i,
    input riscv::pmp_access_t access_type_i,
    input riscv::priv_lvl_t priv_lvl_i,
    // Configuration
    input logic [avoid_neg(CVA6Cfg.NrPMPEntries-1):0][CVA6Cfg.PLEN-3:0] conf_addr_i,
    input riscv::pmpcfg_t [avoid_neg(CVA6Cfg.NrPMPEntries-1):0] conf_i,
    // Output
    output logic allow_o
);
  // if there are no PMPs we can always grant the access.
  if (CVA6Cfg.NrPMPEntries > 0) begin : gen_pmp
    logic [(CVA6Cfg.NrPMPEntries > 0 ? CVA6Cfg.NrPMPEntries-1 : 0):0] match;
    logic [(CVA6Cfg.NrPMPEntries > 0 ? CVA6Cfg.NrPMPEntries-1 : 0):0] pmp_active;
    logic [(CVA6Cfg.NrPMPEntries > 0 ? CVA6Cfg.NrPMPEntries-1 : 0):0] pmp_match_taken;
    logic [(CVA6Cfg.NrPMPEntries > 0 ? CVA6Cfg.NrPMPEntries-1 : 0):0] pmp_access_ok;
    logic [(CVA6Cfg.NrPMPEntries > 0 ? CVA6Cfg.NrPMPEntries-1 : 0):0] pmp_prior_match;
    logic [(CVA6Cfg.NrPMPEntries > 0 ? CVA6Cfg.NrPMPEntries-1 : 0):0] pmp_first_match;
    logic pmp_mmode;

    for (genvar i = 0; i < CVA6Cfg.NrPMPEntries; i++) begin
      logic [CVA6Cfg.PLEN-3:0] conf_addr_prev;

      assign conf_addr_prev = (i == 0) ? '0 : conf_addr_i[i-1];

      pmp_entry #(
          .CVA6Cfg(CVA6Cfg)
      ) i_pmp_entry (
          .addr_i          (addr_i),
          .conf_addr_i     (conf_addr_i[i]),
          .conf_addr_prev_i(conf_addr_prev),
          .conf_addr_mode_i(conf_i[i].addr_mode),
          .match_o         (match[i])
      );
    end

    for (genvar i = 0; i < CVA6Cfg.NrPMPEntries; i++) begin : gen_pmp_allow
      // Either we are in S/U mode, or the config is locked and also applies in M mode.
      assign pmp_active[i] = (((priv_lvl_i != riscv::PRIV_LVL_M) ||
                               conf_i[i].locked) === 1'b1);
      assign pmp_match_taken[i] = pmp_active[i] & (match[i] === 1'b1);
      assign pmp_access_ok[i] =
          (((access_type_i & conf_i[i].access_type) != access_type_i) === 1'b1)
              ? 1'b0
              : 1'b1;
      if (i == 0) begin : gen_first_entry
        assign pmp_prior_match[i] = 1'b0;
      end else begin : gen_later_entry
        assign pmp_prior_match[i] = |pmp_match_taken[i-1:0];
      end
      assign pmp_first_match[i] = pmp_match_taken[i] & ~pmp_prior_match[i];
    end

    assign pmp_mmode = (priv_lvl_i == riscv::PRIV_LVL_M) === 1'b1;
    assign allow_o = (|pmp_first_match) ? |(pmp_first_match & pmp_access_ok) :
                                          pmp_mmode;
  end else assign allow_o = 1'b1;

endmodule
