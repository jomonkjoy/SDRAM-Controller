module sdram_controller (
    input logic clk,
    input logic rst_n,
    
    // Host interface
    input  logic        req,
    input  logic        rw,
    input  logic [23:0] addr,
    input  logic [31:0] data_in,
    output logic [31:0] data_out,
    output logic        busy,
    
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

    // SDRAM timing parameters (example values, adjust as needed)
    localparam tRC  = 7;   // Row cycle time
    localparam tRAS = 5;   // Row active time
    localparam tRP  = 2;   // Row precharge time

    // Command encoding
    localparam CMD_NOP      = 4'b0111;
    localparam CMD_ACTIVE   = 4'b0011;
    localparam CMD_READ     = 4'b0101;
    localparam CMD_WRITE    = 4'b0100;
    localparam CMD_PRECHARGE = 4'b0010;

    // State machine logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
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
                if (req) begin
                    next_state = ACTIVE;
                    cmd = CMD_ACTIVE;
                end else begin
                    busy = 1'b0;
                end
            end
            ACTIVE: begin
                if (counter == tRAS - 1) begin
                    next_state = rw ? WRITE : READ;
                    cmd = rw ? CMD_WRITE : CMD_READ;
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
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            counter <= 4'd0;
        else if (next_state != current_state)
            counter <= 4'd0;
        else
            counter <= counter + 4'd1;
    end

    // Output assignments
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = cmd;
    assign sdram_addr = (current_state == ACTIVE) ? addr[22:10] : 
                        (current_state == READ || current_state == WRITE) ? {4'b0000, addr[9:1]} : 
                        13'b0;
    assign sdram_ba = addr[23:22];
    assign sdram_cke = 1'b1;
    assign sdram_clk = clk;

    // Data path logic (simplified, expand as needed)
    assign sdram_data = (current_state == WRITE) ? data_in : 32'bz;
    always_ff @(posedge clk) begin
        if (current_state == READ && counter == 1)
            data_out <= sdram_data;
    end

endmodule