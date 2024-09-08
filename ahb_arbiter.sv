// AHB Arbiter Module
module ahb_arbiter #(
    parameter NUM_MASTERS = 4
) (
    input  logic                      hclk,
    input  logic                      hresetn,
    input  logic [NUM_MASTERS-1:0]    request,
    output logic [NUM_MASTERS-1:0]    grant,
    output logic [$clog2(NUM_MASTERS)-1:0] selected_master
);

    logic [NUM_MASTERS-1:0] priority_mask;
    logic [$clog2(NUM_MASTERS)-1:0] current_priority;

    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            priority_mask <= '1;
            current_priority <= '0;
            grant <= '0;
            selected_master <= '0;
        end else begin
            if (|(request & priority_mask)) begin
                // Grant to highest priority requesting master
                for (int i = NUM_MASTERS - 1; i >= 0; i--) begin
                    if (request[i] && priority_mask[i]) begin
                        grant <= '0;
                        grant[i] <= 1'b1;
                        selected_master <= i;
                        // Update priority for next cycle
                        priority_mask[i] <= 1'b0;
                        if (i == 0)
                            priority_mask <= '1;
                        break;
                    end
                end
            end else if (|request) begin
                // If no high priority request, reset mask and grant
                priority_mask <= '1;
            end else begin
                // No requests, clear grant
                grant <= '0;
            end
        end
    end

endmodule