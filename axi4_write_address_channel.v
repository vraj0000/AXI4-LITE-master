`timescale 1ns/1ps

module axi4_write_address_channel #(
    parameter ADDR_WIDTH = 32 // Parameter for the address bus width
) (
    // Global Signals
    input  wire                   ACLK,      // Clock source
    input  wire                   ARESETN,   // Global reset (active low)

    // Master-side Control and Data Inputs
    input  wire                   STARTWA,   // Signal to start a Write Address transaction
    input  wire [ADDR_WIDTH-1:0]  wa_addr,   // Write address from the master

    // AXI4-Lite Write Address Channel Interface (Master outputs/Slave inputs)
    output wire [ADDR_WIDTH-1:0]  AWADDR,    // Write address output to subordinate
    output wire [2:0]             AWPROT,    // Protection type output to subordinate
    output wire                   AWVALID,   // Write address valid output to subordinate
    input  wire                   AWREADY,   // Write address ready input from subordinate

    // Status Outputs for Top Module
    output wire                   aw_IDLE,   // Indicates if the AW channel is idle
    output wire                   aw_DONE    // Indicates if the AW transaction is complete
);

    // Internal registers for AXI4 outputs
    reg  [ADDR_WIDTH-1:0]         awaddr_r;
    reg  [2:0]                    awprot_r;
    reg                           awvalid_r;

    // Internal status registers
    reg                           aw_idle_r;
    reg                           aw_done_r;

    // Assign outputs from internal registers
    assign AWADDR  = awaddr_r;
    assign AWPROT  = awprot_r;
    assign AWVALID = awvalid_r;

    assign aw_IDLE = aw_idle_r;
    assign aw_DONE = aw_done_r;

    // State parameters for the FSM
    localparam aw_idle_s = 1'b0; // Idle state: waiting for a transaction request
    localparam aw_send_s = 1'b1; // Send state: asserting AWVALID and waiting for AWREADY

    reg state, state_n; // Current and next state registers

    // State register (FSM sequential logic)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            state <= aw_idle_s; // Reset to idle state
        end else begin          
            state <= state_n;   // Update state on clock edge
        end
    end

    // Next-state logic (FSM combinational logic)
    always @(*) begin
        state_n = state; // Default: stay in current state
        aw_idle_r = 1'b0; // Default deassert aw_idle_r

        case (state)
            aw_idle_s: begin
                aw_idle_r = 1'b1; // Assert idle status
                // If STARTWA is asserted, transition to send state
                if (STARTWA) begin
                    state_n = aw_send_s;
                end
            end
            aw_send_s: begin
                // If the handshake (AWVALID && AWREADY) completes, return to idle
                if (AWREADY && awvalid_r) begin // Use awvalid_r as it reflects the output state
                    state_n = aw_idle_s;
                end
            end
        endcase
    end

    // Output registers (Sequential logic for AXI4 signals and status)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            // Reset all outputs to their default inactive states
            awaddr_r  <= {ADDR_WIDTH{1'b0}};
            awprot_r  <= 3'b000;
            awvalid_r <= 1'b0;
            aw_done_r <= 1'b0; // No transaction done
        end else begin
            // Default assignments for signals that are pulsed or deasserted
            aw_done_r <= 1'b0; // aw_done is a single-cycle pulse

            case (state)
                aw_idle_s: begin
                    awvalid_r <= 1'b0; // Deassert AWVALID when idle
                    if (STARTWA) begin
                        // Load address and protection, assert AWVALID to start transaction
                        awaddr_r  <= wa_addr;
                        awprot_r  <= 3'b000; // Assuming fixed protection for AXI4-Lite (e.g., non-secure, data, privileged)
                        awvalid_r <= 1'b1;   // Assert AWVALID
                    end
                end
                aw_send_s: begin
                    // AWVALID remains asserted until AWREADY is high
                    if (AWREADY && awvalid_r) begin // Check for handshake completion
                        awvalid_r <= 1'b0; // Deassert AWVALID after handshake
                        aw_done_r <= 1'b1; // Assert aw_DONE for one cycle to indicate completion
                    end else begin
                        awvalid_r <= 1'b1; // Keep AWVALID asserted if handshake not complete
                    end
                end
            endcase
        end
    end

endmodule
