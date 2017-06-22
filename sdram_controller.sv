module sdram_controller #(
    parameter SIMULATION = 0,
    parameter CLK_PERIOD_NS = 10,
    parameter ROW_WIDTH = 13,
    parameter COL_WIDTH = 9,
    parameter BANK_WIDTH = 2,

    parameter SDRADDR_WIDTH = ROW_WIDTH > COL_WIDTH ? ROW_WIDTH : COL_WIDTH,
    parameter HADDR_WIDTH = BANK_WIDTH + ROW_WIDTH + COL_WIDTH
) (
    input  logic [HADDR_WIDTH-1:0]   wr_addr,
    input  logic [15:0]              wr_data,
    input  logic                     wr_enable,

    input  logic [HADDR_WIDTH-1:0]   rd_addr,
    output logic [15:0]              rd_data,
    input  logic                     rd_enable,
    output logic                     rd_ready,

    output logic                     busy,
    input  logic                     rst_n,
    input  logic                     clk,

    output logic [SDRADDR_WIDTH-1:0] addr = 0,
    output logic [BANK_WIDTH-1:0]    bank_addr = 0,
    inout  logic [15:0]              data,
    output logic                     clock_enable,
    output logic                     cs_n,
    output logic                     ras_n,
    output logic                     cas_n,
    output logic                     we_n,
    output logic                     data_mask_low,
    output logic                     data_mask_high
);

logic rst;
assign rst = !rst_n;

// state defining SDRAM controller operations
typedef enum {
    IDLE,
    INITIALIZE,
    INIT_PRECHARGE_ALL,
    MODE_REG_SET_ENDLL,
    MODE_REG_SET_RESETDLL,
    PRECHARGE_ALL,
    INIT_AUTO_REFRESH1,
    INIT_AUTO_REFRESH2,
    MODE_REG_SET_UNRESETDLL,
    NOP,
    READ_ACTIVE,
    WRITE_ACTIVE,
    READ,
    WRITE,
    BURST_TERMINATE,
    PRECHARGE,
    AUTO_REFRESH,
    MODE_REG_SET
} state_type;

state_type state = IDLE;

// wait 200us for SDRAM Initialization
localparam INIT_WAIT = SIMULATION ? 8 : 200000/CLK_PERIOD_NS;
localparam RESETDLL_WAIT = SIMULATION ? 8 : 200;
localparam COUNT_WIDTH = $clog2(INIT_WAIT);

logic [COUNT_WIDTH-1:0] count = {COUNT_WIDTH{1'b0}};

typedef struct packed {
    logic [1:0] ba;
    logic [6:0] op_mode;
    logic [2:0] cas_latency;
    logic [0:0] burst_type;
    logic [2:0] burst_length;
} mode_reg_struct;

mode_reg_struct mode_reg = '{2'd0,7'd0,3'd3,1'b0,3'b1};

logic [SDRADDR_WIDTH-1:0] row_ad = 0;
logic [SDRADDR_WIDTH-1:0] col_ad = 0;
logic [BANK_WIDTH-1:0]    bank_ad = 0;

// bank address & addess bus generation
always_ff @(posedge clk) begin
    case (state)
        READ,WRITE : begin
            bank_addr <= bank_ad;
            addr <= col_ad;
        end
        READ_ACTIVE,WRITE_ACTIVE : begin
            bank_addr <= bank_ad;
            addr <= row_ad;
        end
    endcase
end

// clock enable bit generation
always_ff @(posedge clk) begin
    if (rst) begin
        clock_enable <= 1'b0;
    end else if (state == IDLE | state == INITIALIZE) begin
        clock_enable <= 1'b0;
    end else begin
        clock_enable <= 1'b1;
    end
end

// state-machine defenition for SDRAM Controller
always_ff @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        count <= {COUNT_WIDTH{1'b0}};
    end else begin
        case (state)
            IDLE : begin
                state <= INITIALIZE;
            end
            INITIALIZE : begin
                if (count >= INIT_WAIT-1) begin
                    state <= INIT_PRECHARGE_ALL;
                    count <= {COUNT_WIDTH{1'b0}};
                end else begin
                    count <= count + 1;
                end
            end
            INIT_PRECHARGE_ALL : begin
                state <= MODE_REG_SET_ENDLL;
            end
            MODE_REG_SET_ENDLL : begin
                state <= MODE_REG_SET_RESETDLL;
            end
            MODE_REG_SET_RESETDLL : begin
                if (count >= RESETDLL_WAIT-1) begin
                    state <= PRECHARGE_ALL;
                    count <= {COUNT_WIDTH{1'b0}};
                end else begin
                    count <= count + 1;
                end
            end
            PRECHARGE_ALL : begin
                state <= INIT_AUTO_REFRESH1;
            end
            INIT_AUTO_REFRESH1 : begin
                state <= INIT_AUTO_REFRESH2;
            end
            INIT_AUTO_REFRESH2 : begin
                state <= MODE_REG_SET_UNRESETDLL;
            end
            MODE_REG_SET_UNRESETDLL : begin
                state <= NOP;
            end
            NOP : begin
                if (rd_enable) begin
                    state <= READ_ACTIVE;
                end else if (wr_enable) begin
                    state <= WRITE_ACTIVE;
                end
            end
            READ_ACTIVE : begin
                state <= READ;
            end
            WRITE_ACTIVE : begin
                state <= WRITE;
            end
            READ : begin
                if (count >= mode_reg.burst_length-1) begin
                    state <= NOP;
                    count <= {COUNT_WIDTH{1'b0}};
                end else begin
                    count <= count + 1;
                end
            end
            WRITE : begin
                if (count >= mode_reg.burst_length-1) begin
                    state <= NOP;
                    count <= {COUNT_WIDTH{1'b0}};
                end else begin
                    count <= count + 1;
                end
            end
            BURST_TERMINATE : begin
                state <= NOP;
            end
            PRECHARGE : begin
                state <= NOP;
            end
            AUTO_REFRESH : begin
                state <= NOP;
            end
            MODE_REG_SET : begin
                state <= NOP;
            end
            default : begin
                state <= IDLE;
            end
        endcase
    end
end

// command and control signal generation
always_ff @(posedge clk) begin
    if (rst) begin
        cs_n  <= 1'b1;
        ras_n <= 1'b1;
        cas_n <= 1'b1;
        we_n  <= 1'b1;
    end else begin
        case (state)
            INITIALIZE,NOP : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b1;
                cas_n <= 1'b1;
                we_n  <= 1'b1;
            end
            READ_ACTIVE,WRITE_ACTIVE : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b0;
                cas_n <= 1'b1;
                we_n  <= 1'b1;
            end
            READ : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b1;
                cas_n <= 1'b0;
                we_n  <= 1'b1;
            end
            WRITE : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b1;
                cas_n <= 1'b0;
                we_n  <= 1'b0;
            end
            BURST_TERMINATE : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b1;
                cas_n <= 1'b1;
                we_n  <= 1'b0;
            end
            INIT_PRECHARGE_ALL,PRECHARGE_ALL,PRECHARGE : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b0;
                cas_n <= 1'b1;
                we_n  <= 1'b0;
            end
            INIT_AUTO_REFRESH1,INIT_AUTO_REFRESH2,AUTO_REFRESH : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b0;
                cas_n <= 1'b0;
                we_n  <= 1'b1;
            end
            MODE_REG_SET_ENDLL,MODE_REG_SET_RESETDLL,MODE_REG_SET_UNRESETDLL,MODE_REG_SET : begin
                cs_n  <= 1'b0;
                ras_n <= 1'b0;
                cas_n <= 1'b0;
                we_n  <= 1'b0;
            end
            // SDRAM default operation is NOP
            default : begin
                cs_n  <= 1'b1;
                ras_n <= 1'b1;
                cas_n <= 1'b1;
                we_n  <= 1'b1;
            end
        endcase
    end
end

endmodule
