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
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 15.08.2018
// Description: Ariane cache subsystem that is compatible with the OpenPiton
//              coherent memory system.
//
//              Define PITON_ARIANE if you want to use this cache.
//              Define CVA6Cfg.DCacheType if you want to use this cache
//              with a standard 64 bit AXI interface instead of the OpenPiton
//              L1.5 interface.


module wt_cache_subsystem
  import ariane_pkg::*;
  import wt_cache_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg        = config_pkg::cva6_cfg_empty,
    parameter type                   icache_areq_t  = logic,
    parameter type                   icache_arsp_t  = logic,
    parameter type                   icache_dreq_t  = logic,
    parameter type                   icache_drsp_t  = logic,
    parameter type                   dcache_req_i_t = logic,
    parameter type                   dcache_req_o_t = logic,
    parameter type                   icache_req_t   = logic,
    parameter type                   icache_rtrn_t  = logic,
    parameter int unsigned           NumPorts       = 4,
    parameter type                   noc_req_t      = logic,
    parameter type                   noc_resp_t     = logic
) (
    input logic clk_i,
    input logic rst_ni,
    // I$
    input logic icache_en_i,  // enable icache (or bypass e.g: in debug mode)
    input logic icache_flush_i,  // flush the icache, flush and kill have to be asserted together
    output logic icache_miss_o,  // to performance counter
    // address translation requests
    input icache_areq_t icache_areq_i,  // to/from frontend
    output icache_arsp_t icache_areq_o,
    // data requests
    input icache_dreq_t icache_dreq_i,  // to/from frontend
    output icache_drsp_t icache_dreq_o,
    // D$
    // Cache management
    input logic dcache_enable_i,  // from CSR
    input logic dcache_flush_i,  // high until acknowledged
    output logic                           dcache_flush_ack_o,     // send a single cycle acknowledge signal when the cache is flushed
    output logic dcache_miss_o,  // we missed on a ld/st
    // For Performance Counter
    output logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_vld_bits_o,
    // AMO interface
    input amo_req_t dcache_amo_req_i,
    output amo_resp_t dcache_amo_resp_o,
    input logic mbe_i,
    // Request ports
    input dcache_req_i_t [NumPorts-1:0] dcache_req_ports_i,  // to/from LSU
    output dcache_req_o_t [NumPorts-1:0] dcache_req_ports_o,  // to/from LSU
    // writebuffer status
    output logic wbuffer_empty_o,
    output logic wbuffer_not_ni_o,
    // memory side
    output noc_req_t noc_req_o,
    input noc_resp_t noc_resp_i,
    // Invalidations
    input logic [63:0] inval_addr_i,
    input logic inval_valid_i,
    output logic inval_ready_o
    // TODO: interrupt interface
);

  // dcache interface
  localparam type dcache_inval_t = struct packed {
    logic                                      vld;  // invalidate only affected way
    logic                                      all;  // invalidate all ways
    logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0]     idx;  // physical address to invalidate
    logic [CVA6Cfg.DCACHE_SET_ASSOC_WIDTH-1:0] way;  // way to invalidate
  };

  localparam type dcache_req_t = struct packed {
    wt_cache_pkg::dcache_out_t rtype;  // see definitions above
    logic [2:0]                                      size;        // transaction size: 000=Byte 001=2Byte; 010=4Byte; 011=8Byte; 111=Cache line (16/32Byte)
    logic [CVA6Cfg.DCACHE_SET_ASSOC_WIDTH-1:0] way;  // way to replace
    logic [CVA6Cfg.PLEN-1:0] paddr;  // physical address
    logic [CVA6Cfg.XLEN-1:0] data;  // word width of processor (no block stores at the moment)
    logic [CVA6Cfg.DCACHE_USER_WIDTH-1:0]          user;        // user width of processor (no block stores at the moment)
    logic nc;  // noncacheable
    logic [CVA6Cfg.MEM_TID_WIDTH-1:0] tid;  // thread id (used as transaction id in Ariane)
    ariane_pkg::amo_t amo_op;  // amo opcode
  };

  localparam type dcache_rtrn_t = struct packed {
    wt_cache_pkg::dcache_in_t rtype;  // see definitions above
    logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0] data;  // full cache line width
    logic [CVA6Cfg.DCACHE_USER_LINE_WIDTH-1:0] user;  // user bits
    dcache_inval_t inv;  // invalidation vector
    logic [CVA6Cfg.MEM_TID_WIDTH-1:0] tid;  // thread id (used as transaction id in Ariane)
  };

  localparam int unsigned IcacheAreqWidth = $bits(icache_areq_t);
  localparam int unsigned IcacheArspWidth = $bits(icache_arsp_t);
  localparam int unsigned IcacheDreqWidth = $bits(icache_dreq_t);
  localparam int unsigned IcacheDrspWidth = $bits(icache_drsp_t);
  localparam int unsigned IcacheReqWidth = $bits(icache_req_t);
  localparam int unsigned IcacheRtrnWidth = $bits(icache_rtrn_t);
`ifndef PITON_ARIANE
  localparam int unsigned NocReqWidth = $bits(noc_req_t);
  localparam int unsigned NocRespWidth = $bits(noc_resp_t);
`endif
  logic [IcacheAreqWidth-1:0] icache_areq_i_flat;
  logic [IcacheArspWidth-1:0] icache_areq_o_flat;
  logic [IcacheDreqWidth-1:0] icache_dreq_i_flat;
  logic [IcacheDrspWidth-1:0] icache_dreq_o_flat;
`ifndef PITON_ARIANE
  logic [NocReqWidth-1:0] noc_req_o_flat;
  logic [NocRespWidth-1:0] noc_resp_i_flat;
`endif
  assign icache_areq_i_flat = icache_areq_i;
  assign icache_areq_o = icache_areq_o_flat;
  assign icache_dreq_i_flat = icache_dreq_i;
  assign icache_dreq_o = icache_dreq_o_flat;
`ifndef PITON_ARIANE
  assign noc_req_o = noc_req_o_flat;
  assign noc_resp_i_flat = noc_resp_i;
`endif
  logic icache_adapter_data_req, adapter_icache_data_ack, adapter_icache_rtrn_vld;
  logic [IcacheReqWidth-1:0]  icache_adapter;
  logic [IcacheRtrnWidth-1:0] adapter_icache;


  localparam int unsigned DcacheReqIWidth = $bits(dcache_req_i_t);
  localparam int unsigned DcacheReqOWidth = $bits(dcache_req_o_t);
  localparam int unsigned DcacheReqWidth = $bits(dcache_req_t);
  localparam int unsigned DcacheRtrnWidth = $bits(dcache_rtrn_t);
  localparam int unsigned DcacheInvalWidth = $bits(dcache_inval_t);
  logic [NumPorts-1:0][DcacheReqIWidth-1:0] dcache_req_ports_i_flat;
  logic [NumPorts-1:0][DcacheReqOWidth-1:0] dcache_req_ports_o_flat;
  assign dcache_req_ports_i_flat = dcache_req_ports_i;
  assign dcache_req_ports_o = dcache_req_ports_o_flat;
  logic dcache_adapter_data_req, adapter_dcache_data_ack, adapter_dcache_rtrn_vld;
  logic [DcacheReqWidth-1:0]  dcache_adapter;
  logic [DcacheRtrnWidth-1:0] adapter_dcache;

  cva6_icache #(
      // use ID 0 for icache reads
      .CVA6Cfg(CVA6Cfg),
      .IcacheAreqWidth(IcacheAreqWidth),
      .IcacheArspWidth(IcacheArspWidth),
      .IcacheDreqWidth(IcacheDreqWidth),
      .IcacheDrspWidth(IcacheDrspWidth),
      .IcacheReqWidth(IcacheReqWidth),
      .IcacheRtrnWidth(IcacheRtrnWidth),
      .RdTxId(0)
  ) i_cva6_icache (
      .clk_i         (clk_i),
      .rst_ni        (rst_ni),
      .flush_i       (icache_flush_i),
      .en_i          (icache_en_i),
      .miss_o        (icache_miss_o),
      .areq_i_flat   (icache_areq_i_flat),
      .areq_o_flat   (icache_areq_o_flat),
      .dreq_i_flat   (icache_dreq_i_flat),
      .dreq_o_flat   (icache_dreq_o_flat),
      .mem_rtrn_vld_i(adapter_icache_rtrn_vld),
      .mem_rtrn_i_flat(adapter_icache),
      .mem_data_req_o(icache_adapter_data_req),
      .mem_data_ack_i(adapter_icache_data_ack),
      .mem_data_o_flat(icache_adapter)
  );


  // Note:
  // Ports 0/1 for PTW and LD unit are read only.
  // they have equal prio and are RR arbited
  // Port 2 is write only and goes into the merging write buffer
  wt_dcache #(
      .CVA6Cfg(CVA6Cfg),
      .DcacheReqIWidth(DcacheReqIWidth),
      .DcacheReqOWidth(DcacheReqOWidth),
      .DcacheReqWidth(DcacheReqWidth),
      .DcacheRtrnWidth(DcacheRtrnWidth),
      // use ID 1 for dcache reads and amos. note that the writebuffer
      // uses all IDs up to DCACHE_MAX_TX-1 for write transactions.
      .RdAmoTxId(1)
  ) i_wt_dcache (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .enable_i        (dcache_enable_i),
      .flush_i         (dcache_flush_i),
      .flush_ack_o     (dcache_flush_ack_o),
      .miss_o          (dcache_miss_o),
      .wbuffer_empty_o (wbuffer_empty_o),
      .wbuffer_not_ni_o(wbuffer_not_ni_o),
      .amo_req_i       (dcache_amo_req_i),
      .amo_resp_o      (dcache_amo_resp_o),
      .mbe_i           (mbe_i),
      .req_ports_i_flat(dcache_req_ports_i_flat),
      .req_ports_o_flat(dcache_req_ports_o_flat),
      .miss_vld_bits_o (miss_vld_bits_o),
      .mem_rtrn_vld_i  (adapter_dcache_rtrn_vld),
      .mem_rtrn_i_flat (adapter_dcache),
      .mem_data_req_o  (dcache_adapter_data_req),
      .mem_data_ack_i  (adapter_dcache_data_ack),
      .mem_data_o_flat (dcache_adapter)
  );


  ///////////////////////////////////////////////////////
  // memory plumbing, either use 64bit AXI port or native
  // L15 cache interface (derived from OpenSPARC CCX).
  ///////////////////////////////////////////////////////

`ifdef PITON_ARIANE
  icache_req_t  icache_adapter_typed;
  icache_rtrn_t adapter_icache_typed;
  dcache_req_t  dcache_adapter_typed;
  dcache_rtrn_t adapter_dcache_typed;
  assign icache_adapter_typed = icache_adapter;
  assign adapter_icache = adapter_icache_typed;
  assign dcache_adapter_typed = dcache_adapter;
  assign adapter_dcache = adapter_dcache_typed;

  wt_l15_adapter #(
      .CVA6Cfg(CVA6Cfg),
      .dcache_req_t(dcache_req_t),
      .dcache_rtrn_t(dcache_rtrn_t),
      .icache_req_t(icache_req_t),
      .icache_rtrn_t(icache_rtrn_t)
  ) i_adapter (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .icache_data_req_i(icache_adapter_data_req),
      .icache_data_ack_o(adapter_icache_data_ack),
      .icache_data_i    (icache_adapter_typed),
      .icache_rtrn_vld_o(adapter_icache_rtrn_vld),
      .icache_rtrn_o    (adapter_icache_typed),
      .dcache_data_req_i(dcache_adapter_data_req),
      .dcache_data_ack_o(adapter_dcache_data_ack),
      .dcache_data_i    (dcache_adapter_typed),
      .dcache_rtrn_vld_o(adapter_dcache_rtrn_vld),
      .dcache_rtrn_o    (adapter_dcache_typed),
      .l15_req_o        (noc_req_o),
      .l15_rtrn_i       (noc_resp_i)
  );
`else
  wt_axi_adapter #(
      .CVA6Cfg(CVA6Cfg),
      .AxiReqWidth(NocReqWidth),
      .AxiRespWidth(NocRespWidth),
      .DcacheReqWidth(DcacheReqWidth),
      .DcacheRtrnWidth(DcacheRtrnWidth),
      .DcacheInvalWidth(DcacheInvalWidth),
      .IcacheReqWidth(IcacheReqWidth),
      .IcacheRtrnWidth(IcacheRtrnWidth)
  ) i_adapter (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .icache_data_req_i(icache_adapter_data_req),
      .icache_data_ack_o(adapter_icache_data_ack),
      .icache_data_i_flat(icache_adapter),
      .icache_rtrn_vld_o(adapter_icache_rtrn_vld),
      .icache_rtrn_o_flat(adapter_icache),
      .dcache_data_req_i(dcache_adapter_data_req),
      .dcache_data_ack_o(adapter_dcache_data_ack),
      .dcache_data_i_flat(dcache_adapter),
      .dcache_rtrn_vld_o(adapter_dcache_rtrn_vld),
      .dcache_rtrn_o_flat(adapter_dcache),
      .axi_req_o_flat   (noc_req_o_flat),
      .axi_resp_i_flat  (noc_resp_i_flat),
      .mbe_i            (mbe_i),
      .inval_addr_i     (inval_addr_i),
      .inval_valid_i    (inval_valid_i),
      .inval_ready_o    (inval_ready_o)
  );
`endif

  ///////////////////////////////////////////////////////
  // assertions
  ///////////////////////////////////////////////////////

  //pragma translate_off
`ifndef VERILATOR
  a_invalid_instruction_fetch :
  assert property (
    @(posedge clk_i) disable iff (!rst_ni) icache_dreq_o.valid |-> (|icache_dreq_o.data) !== 1'hX)
  else
    $warning(
        1,
        "[l1 dcache] reading invalid instructions: vaddr=%08X, data=%08X",
        icache_dreq_o.vaddr,
        icache_dreq_o.data
    );

  for (genvar j = 0; j < CVA6Cfg.XLEN / 8; j++) begin : gen_invalid_write_assertion
    a_invalid_write_data :
    assert property (
      @(posedge clk_i) disable iff (!rst_ni) dcache_req_ports_i[NumPorts-1].data_req |-> dcache_req_ports_i[NumPorts-1].data_be[j] |-> (|dcache_req_ports_i[NumPorts-1].data_wdata[j*8+:8] !== 1'hX))
    else
      $warning(
          1,
          "[l1 dcache] writing invalid data: paddr=%016X, be=%02X, data=%016X, databe=%016X",
          {
            dcache_req_ports_i[NumPorts-1].address_tag, dcache_req_ports_i[NumPorts-1].address_index
          },
          dcache_req_ports_i[NumPorts-1].data_be,
          dcache_req_ports_i[NumPorts-1].data_wdata,
          dcache_req_ports_i[NumPorts-1].data_be & dcache_req_ports_i[NumPorts-1].data_wdata
      );
  end


  for (genvar j = 0; j < NumPorts - 1; j++) begin : gen_assertion
    a_invalid_read_data :
    assert property (
      @(posedge clk_i) disable iff (!rst_ni) dcache_req_ports_o[j].data_rvalid && ~dcache_req_ports_i[j].kill_req |-> (|dcache_req_ports_o[j].data_rdata) !== 1'hX)
    else
      $warning(
          1,
          "[l1 dcache] reading invalid data on port %01d: data=%016X",
          j,
          dcache_req_ports_o[j].data_rdata
      );
  end
`endif
  //pragma translate_on


endmodule  // wt_cache_subsystem
