module ahb_multi_master_sdram_wrapper #(
    parameter NUM_MASTERS = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic                  hclk,
    input  logic                  hresetn,
    
    // AHB Master interfaces
    input  logic [NUM_MASTERS-1:0]        hsel,
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] haddr,
    input  logic [NUM_MASTERS-1:0][1:0]   htrans,
    input  logic [NUM_MASTERS-1:0]        hwrite,
    input  logic [NUM_MASTERS-1:0][2:0]   hsize,
    input  logic [NUM_MASTERS-1:0][2:0]   hburst,
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] hwdata,
    output logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] hrdata,
    output logic [NUM_MASTERS-1:0]        hready,
    output logic [NUM_MASTERS-1:0][1:0]   hresp,
    
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

    // Internal signals for arbitration
    logic [NUM_MASTERS-1:0] request;
    logic [NUM_MASTERS-1:0] grant;
    logic [$clog2(NUM_MASTERS)-1:0] selected_master;

    // Internal signals for SDRAM controller
    logic        sdram_hsel;
    logic [31:0] sdram_haddr;
    logic [1:0]  sdram_htrans;
    logic        sdram_hwrite;
    logic [2:0]  sdram_hsize;
    logic [2:0]  sdram_hburst;
    logic [31:0] sdram_hwdata;
    logic [31:0] sdram_hrdata;
    logic        sdram_hready;
    logic [1:0]  sdram_hresp;

    // Arbiter instantiation
    ahb_arbiter #(
        .NUM_MASTERS(NUM_MASTERS)
    ) arbiter (
        .hclk(hclk),
        .hresetn(hresetn),
        .request(request),
        .grant(grant),
        .selected_master(selected_master)
    );

    // Generate request signals
    genvar i;
    generate
        for (i = 0; i < NUM_MASTERS; i++) begin : gen_request
            assign request[i] = hsel[i] && (htrans[i] != 2'b00);
        end
    endgenerate

    // Mux for selecting master signals
    always_comb begin
        sdram_hsel   = hsel[selected_master];
        sdram_haddr  = haddr[selected_master];
        sdram_htrans = htrans[selected_master];
        sdram_hwrite = hwrite[selected_master];
        sdram_hsize  = hsize[selected_master];
        sdram_hburst = hburst[selected_master];
        sdram_hwdata = hwdata[selected_master];
    end

    // Demux for distributing SDRAM controller responses
    always_comb begin
        for (int j = 0; j < NUM_MASTERS; j++) begin
            if (grant[j]) begin
                hrdata[j] = sdram_hrdata;
                hready[j] = sdram_hready;
                hresp[j]  = sdram_hresp;
            end else begin
                hrdata[j] = '0;
                hready[j] = 1'b1;  // Non-selected masters are always ready
                hresp[j]  = 2'b00; // OKAY response for non-selected masters
            end
        end
    end

    // SDRAM controller instantiation
    ahb_sdram_controller sdram_ctrl (
        .hclk(hclk),
        .hresetn(hresetn),
        .hsel(sdram_hsel),
        .haddr(sdram_haddr),
        .htrans(sdram_htrans),
        .hwrite(sdram_hwrite),
        .hsize(sdram_hsize),
        .hburst(sdram_hburst),
        .hwdata(sdram_hwdata),
        .hrdata(sdram_hrdata),
        .hready(sdram_hready),
        .hresp(sdram_hresp),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_ba(sdram_ba),
        .sdram_addr(sdram_addr),
        .sdram_data(sdram_data),
        .sdram_dqm(sdram_dqm)
    );

endmodule
