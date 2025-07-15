`timescale 1ns/1ps

module axi4_write_response_channel (
    // Global
    input  wire        ACLK,
    input  wire        ARESETN,

    // Master-side start signal
    input  wire        STARTWR, // Signal to start waiting for Write Response

    // AXI4 Write Response Channel Interface (Slave outputs/Master inputs)
    input  wire [1:0]  BRESP,      // Write response from subordinate
    input  wire        BVALID,     // Write response valid from subordinate
    output wire        BREADY,     // Response ready output to subordinate

    // Status
    output wire        b_idle,     // Indicates if the B channel is idle
    output wire        b_done,     // Indicates if the B transaction is complete
    output wire [1:0]  bresp_out   // Write response output to master
);

    // Internal registers for AXI4 outputs
    reg  bready_r;

    // Internal status registers
    reg  b_idle_r;
    reg  b_done_r;
    reg  [1:0] bresp_out_r;

    // Assign outputs from internal registers
    assign BREADY    = bready_r;
    assign b_idle    = b_idle_r;
    assign b_done    = b_done_r;
    assign bresp_out = bresp_out_r;

    // State parameters (matching previous style using localparam)
    localparam b_idle_s = 1'b0; // Idle state: waiting for STARTWR
    localparam b_recv_s = 1'b1; // Receive state: asserting BREADY and waiting for BVALID

    reg state, state_n; // Current and next state registers

    // State register (FSM sequential logic)
    always @(posedge ACLK or negedge ARESETN)
        if (!ARESETN) 
            state <= b_idle_s;
        else          
            state <= state_n;

    // Next-state logic (FSM combinational logic)
    always @(*) begin
        state_n = state;
        b_idle_r = 1'b0; // Default deassert b_idle_r

        case (state)
            b_idle_s: begin
                b_idle_r = 1'b1; // Assert b_idle_r when in idle state
                if (STARTWR) 
                    state_n = b_recv_s;
            end
            b_recv_s: begin
                // Transition back to idle when the handshake (BVALID && BREADY) completes
                if (BVALID && bready_r) 
                    state_n = b_idle_s;
            end
        endcase
    end

    // Output registers (Sequential logic for AXI4 signals and status)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            bready_r      <= 1'b0;
            b_done_r      <= 1'b0;
            bresp_out_r   <= 2'b00;
        end else begin
            // Default assignments
            b_done_r <= 1'b0; // Default b_done_r low, assert only on transaction completion

            case (state)
                b_idle_s: begin
                    bready_r <= 1'b0; // Deassert BREADY when idle
                    if (STARTWR) begin
                        bready_r <= 1'b1; // Assert BREADY when starting to wait for response
                    end
                end
                b_recv_s: begin
                    // Check if the slave asserted BVALID
                    if (BVALID) begin
                        // Handshake complete, deassert BREADY and capture BRESP
                        bready_r    <= 1'b0;
                        b_done_r    <= 1'b1; // Indicate transaction completion
                        bresp_out_r <= BRESP;
                    end else begin
                        bready_r <= 1'b1; // Keep BREADY asserted if BVALID not yet high
                    end
                end
            endcase
        end
    end

endmodule
