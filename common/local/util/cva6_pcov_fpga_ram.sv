// Local FPGA RAM models for the CVA6 pcov flow.
//
// These modules keep the same public interfaces as the fpga-support RAMs used
// by CVA6, but avoid translate_off/assert/random constructs that do not survive
// the current sv-sv pipeline cleanly.  The implementations are still plain
// synthesizable inferred RAMs and are also usable by Verilator simulation.

module SyncDpRam #(
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned OUT_REGS   = 0,
  parameter int unsigned SIM_INIT   = 0
) (
  input  logic                  Clk_CI,
  input  logic                  Rst_RBI,
  input  logic                  CSelA_SI,
  input  logic                  WrEnA_SI,
  input  logic [DATA_WIDTH-1:0] WrDataA_DI,
  input  logic [ADDR_WIDTH-1:0] AddrA_DI,
  output logic [DATA_WIDTH-1:0] RdDataA_DO,
  input  logic                  CSelB_SI,
  input  logic                  WrEnB_SI,
  input  logic [DATA_WIDTH-1:0] WrDataB_DI,
  input  logic [ADDR_WIDTH-1:0] AddrB_DI,
  output logic [DATA_WIDTH-1:0] RdDataB_DO
);

  logic [DATA_WIDTH-1:0] mem [DATA_DEPTH-1:0] = '{default: '0};
  logic [DATA_WIDTH-1:0] rdata_a_d, rdata_b_d;
  logic [DATA_WIDTH-1:0] rdata_a_q, rdata_b_q;

  always_ff @(posedge Clk_CI) begin
    if (CSelA_SI) begin
      if (WrEnA_SI) mem[AddrA_DI] <= WrDataA_DI;
      rdata_a_d <= mem[AddrA_DI];
    end
    if (CSelB_SI) begin
      if (WrEnB_SI) mem[AddrB_DI] <= WrDataB_DI;
      rdata_b_d <= mem[AddrB_DI];
    end
  end

  if (OUT_REGS > 0) begin : gen_out_regs
    always_ff @(posedge Clk_CI or negedge Rst_RBI) begin
      if (!Rst_RBI) begin
        rdata_a_q <= '0;
        rdata_b_q <= '0;
      end else begin
        rdata_a_q <= rdata_a_d;
        rdata_b_q <= rdata_b_d;
      end
    end
    assign RdDataA_DO = rdata_a_q;
    assign RdDataB_DO = rdata_b_q;
  end else begin : gen_out_bypass
    assign RdDataA_DO = rdata_a_d;
    assign RdDataB_DO = rdata_b_d;
  end

endmodule

module AsyncDpRam #(
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned DATA_WIDTH = 32
) (
  input  logic                  Clk_CI,
  input  logic                  WrEn_SI,
  input  logic [ADDR_WIDTH-1:0] WrAddr_DI,
  input  logic [DATA_WIDTH-1:0] WrData_DI,
  input  logic [ADDR_WIDTH-1:0] RdAddr_DI,
  output logic [DATA_WIDTH-1:0] RdData_DO
);

  logic [DATA_WIDTH-1:0] mem [DATA_DEPTH-1:0] = '{default: '0};

  always_ff @(posedge Clk_CI) begin
    if (WrEn_SI) mem[WrAddr_DI] <= WrData_DI;
  end

  assign RdData_DO = mem[RdAddr_DI];

endmodule

module SyncDpRam_ind_r_w #(
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned DATA_WIDTH = 32
) (
  input  logic                  Clk_CI,
  input  logic                  WrEn_SI,
  input  logic [ADDR_WIDTH-1:0] WrAddr_DI,
  input  logic [DATA_WIDTH-1:0] WrData_DI,
  input  logic [ADDR_WIDTH-1:0] RdAddr_DI,
  output logic [DATA_WIDTH-1:0] RdData_DO
);

  logic [DATA_WIDTH-1:0] mem [DATA_DEPTH-1:0] = '{default: '0};

  always_ff @(posedge Clk_CI) begin
    if (WrEn_SI) mem[WrAddr_DI] <= WrData_DI;
    RdData_DO <= mem[RdAddr_DI];
  end

endmodule

module AsyncThreePortRam #(
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned DATA_WIDTH = 32
) (
  input  logic                  Clk_CI,
  input  logic                  WrEn_SI,
  input  logic [ADDR_WIDTH-1:0] WrAddr_DI,
  input  logic [DATA_WIDTH-1:0] WrData_DI,
  input  logic [ADDR_WIDTH-1:0] RdAddr_DI_0,
  input  logic [ADDR_WIDTH-1:0] RdAddr_DI_1,
  output logic [DATA_WIDTH-1:0] RdData_DO_0,
  output logic [DATA_WIDTH-1:0] RdData_DO_1
);

  logic [DATA_WIDTH-1:0] mem [DATA_DEPTH-1:0] = '{default: '0};

  always_ff @(posedge Clk_CI) begin
    if (WrEn_SI) mem[WrAddr_DI] <= WrData_DI;
  end

  assign RdData_DO_0 = mem[RdAddr_DI_0];
  assign RdData_DO_1 = mem[RdAddr_DI_1];

endmodule

module SyncThreePortRam #(
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned DATA_WIDTH = 32
) (
  input  logic                  Clk_CI,
  input  logic                  WrEn_SI,
  input  logic [ADDR_WIDTH-1:0] WrAddr_DI,
  input  logic [DATA_WIDTH-1:0] WrData_DI,
  input  logic [ADDR_WIDTH-1:0] RdAddr_DI_0,
  input  logic [ADDR_WIDTH-1:0] RdAddr_DI_1,
  output logic [DATA_WIDTH-1:0] RdData_DO_0,
  output logic [DATA_WIDTH-1:0] RdData_DO_1
);

  logic [DATA_WIDTH-1:0] mem [DATA_DEPTH-1:0] = '{default: '0};

  always_ff @(posedge Clk_CI) begin
    if (WrEn_SI) mem[WrAddr_DI] <= WrData_DI;
    RdData_DO_0 <= mem[RdAddr_DI_0];
    RdData_DO_1 <= mem[RdAddr_DI_1];
  end

endmodule

module SyncSpRamBeNx64 #(
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned OUT_REGS   = 0,
  parameter int unsigned SIM_INIT   = 0
) (
  input  logic                  Clk_CI,
  input  logic                  Rst_RBI,
  input  logic                  CSel_SI,
  input  logic                  WrEn_SI,
  input  logic [7:0]            BEn_SI,
  input  logic [63:0]           WrData_DI,
  input  logic [ADDR_WIDTH-1:0] Addr_DI,
  output logic [63:0]           RdData_DO
);

  logic [63:0] mem [DATA_DEPTH-1:0] = '{default: '0};
  logic [63:0] rdata_d, rdata_q;
  logic [63:0] write_mask;
  logic [63:0] write_data;

  assign write_mask = {
    {8{BEn_SI[7]}}, {8{BEn_SI[6]}}, {8{BEn_SI[5]}}, {8{BEn_SI[4]}},
    {8{BEn_SI[3]}}, {8{BEn_SI[2]}}, {8{BEn_SI[1]}}, {8{BEn_SI[0]}}
  };
  assign write_data = (mem[Addr_DI] & ~write_mask) | (WrData_DI & write_mask);

  always_ff @(posedge Clk_CI) begin
    if (CSel_SI) begin
      if (WrEn_SI) mem[Addr_DI] <= write_data;
      rdata_d <= mem[Addr_DI];
    end
  end

  if (OUT_REGS > 0) begin : gen_out_regs
    always_ff @(posedge Clk_CI or negedge Rst_RBI) begin
      if (!Rst_RBI) rdata_q <= '0;
      else rdata_q <= rdata_d;
    end
    assign RdData_DO = rdata_q;
  end else begin : gen_out_bypass
    assign RdData_DO = rdata_d;
  end

endmodule
