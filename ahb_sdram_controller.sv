module ahb_sdram_controller (
    input logic hclk,    // AHB clock
    input logic hresetn, // AHB reset (active low)
    
    // AHB slave interface
    input  logic        hsel,
    input  logic [31:0] haddr,
    input  logic [1:0]  htrans,
    input  logic        hwrite,
    input  logic [2:0]  hsize,
    input  logic [2:0]  hburst,
    input  logic [31:0] hwdata,
    output logic [31:0] hrdata,
    output logic        hready,
    output logic [1:0]  hresp,
    
    // SDRAM interface
    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    output logic [1:0]  sdram_ba,
    output logic [12:0] sdram_addr,
    inout  logic [31:0] sdram_data,
    output logic [3:0]  sdram_dqm
);

    // State machine definition
    typedef enum {IDLE, ACTIVE, READ, WRITE, PRECHARGE} state_t;
    state_t current_state, next_state;

    // Internal signals and registers
    logic [3:0] cmd;
    logic [3:0] counter;
    logic [31:0] addr_reg;
    logic        write_reg;
    logic [31:0] data_reg;
    logic        busy;

    // SDRAM timing parameters (example values, adjust as needed)
    localparam tRC  = 7;   // Row cycle time
    localparam tRAS = 5;   // Row active time
    localparam tRP  = 2;   // Row precharge time

    // Command encoding
    localparam CMD_NOP       = 4'b0111;
    localparam CMD_ACTIVE    = 4'b0011;
    localparam CMD_READ      = 4'b0101;
    localparam CMD_WRITE     = 4'b0100;
    localparam CMD_PRECHARGE = 4'b0010;

    // AHB transfer type encoding
    localparam HTRANS_IDLE   = 2'b00;
    localparam HTRANS_BUSY   = 2'b01;
    localparam HTRANS_NONSEQ = 2'b10;
    localparam HTRANS_SEQ    = 2'b11;

    // State machine logic
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        cmd = CMD_NOP;
        busy = 1'b1;

        case (current_state)
            IDLE: begin
                if (hsel && htrans == HTRANS_NONSEQ) begin
                    next_state = ACTIVE;
                    cmd = CMD_ACTIVE;
                end else begin
                    busy = 1'b0;
                end
            end
            ACTIVE: begin
                if (counter == tRAS - 1) begin
                    next_state = write_reg ? WRITE : READ;
                    cmd = write_reg ? CMD_WRITE : CMD_READ;
                end
            end
            READ: begin
                if (counter == 1) begin
                    next_state = PRECHARGE;
                    cmd = CMD_PRECHARGE;
                end
            end
            WRITE: begin
                if (counter == 1) begin
                    next_state = PRECHARGE;
                    cmd = CMD_PRECHARGE;
                end
            end
            PRECHARGE: begin
                if (counter == tRP - 1) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Counter logic
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            counter <= 4'd0;
        else if (next_state != current_state)
            counter <= 4'd0;
        else
            counter <= counter + 4'd1;
    end

    // AHB interface logic
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            addr_reg <= 32'd0;
            write_reg <= 1'b0;
            data_reg <= 32'd0;
        end else if (hsel && htrans == HTRANS_NONSEQ && current_state == IDLE) begin
            addr_reg <= haddr;
            write_reg <= hwrite;
            if (hwrite)
                data_reg <= hwdata;
        end
    end

    // AHB response
    assign hready = (current_state == IDLE && !busy);
    assign hresp = 2'b00; // OKAY response

    // SDRAM interface assignments
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = cmd;
    assign sdram_addr = (current_state == ACTIVE) ? addr_reg[23:11] : 
                        (current_state == READ || current_state == WRITE) ? {4'b0000, addr_reg[10:2]} : 
                        13'b0;
    assign sdram_ba = addr_reg[25:24];
    assign sdram_cke = 1'b1;
    assign sdram_clk = hclk;

    // Data path logic
    assign sdram_data = (current_state == WRITE) ? data_reg : 32'bz;
    always_ff @(posedge hclk) begin
        if (current_state == READ && counter == 1)
            hrdata <= sdram_data;
    end

endmodule