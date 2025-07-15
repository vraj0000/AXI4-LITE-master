`timescale 1ns/1ps

module axi4_read_data_channel #(
    parameter DATA_WIDTH = 32 // Parameter for the data bus width
) (
    // Global Signals
    input  wire                   ACLK,      // Clock source
    input  wire                   ARESETN,   // Global reset (active low)

    // Master-side Control Input
    input  wire                   STARTRD,   // Signal to start waiting for Read Data

    // AXI4-Lite Read Data Channel Interface (Slave outputs/Master inputs)
    input  wire [DATA_WIDTH-1:0]  RDATA,     // Read data from subordinate
    input  wire [1:0]             RRESP,     // Read response from subordinate
    input  wire                   RVALID,    // Read valid from subordinate
    output wire                   RREADY,    // Read ready output to subordinate

    // Status Outputs for Top Module
    output wire                   r_IDLE,    // Indicates if the R channel is idle
    output wire                   r_DONE,    // Indicates if the R transaction is complete
    output wire [DATA_WIDTH-1:0]  r_DATA_out, // Read data output to master
    output wire [1:0]             rresp_out  // Read response output to master
);

    // Internal registers for AXI4 outputs
    reg                           rready;

    // Internal status registers
    reg                           r_idle;
    reg                           r_done;
    reg  [DATA_WIDTH-1:0]         r_data_out;
    reg  [1:0]                    rresp_out_r; // Renamed to avoid conflict with output port

    // Assign outputs from internal registers
    assign RREADY     = rready;
    assign r_IDLE     = r_idle;
    assign r_DONE     = r_done;
    assign r_DATA_out = r_data_out;
    assign rresp_out  = rresp_out_r;

    // State parameters for the FSM
    localparam r_idle_s = 1'b0; // Idle state: waiting for STARTRD
    localparam r_recv_s = 1'b1; // Receive state: asserting RREADY and waiting for RVALID

    reg state, state_n; // Current and next state registers

    // State register (FSM sequential logic)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN)
            state <= r_idle_s; // Reset to idle state
        else
            state <= state_n;   // Update state on clock edge
    end

    // Next-state logic (FSM combinational logic)
    always @(*) begin
        state_n = state; // Default: stay in current state
        case (state)
            r_idle_s: if (STARTRD) state_n = r_recv_s;
            r_recv_s: if (RVALID && rready) state_n = r_idle_s;
        endcase
    end

    // Output registers (Sequential logic for AXI4 signals and status)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            // Reset all outputs to their default inactive states
            rready       <= 1'b0;
            r_idle       <= 1'b1; // Initially idle
            r_done       <= 1'b0; // No transaction done
            r_data_out   <= {DATA_WIDTH{1'b0}};
            rresp_out_r  <= 2'b00;
        end else begin
            case (state)
                r_idle_s: begin
                    rready       <= 1'b0; // Deassert RREADY when idle
                    r_idle       <= 1'b1; // Assert idle status
                    r_done       <= 1'b0; // No transaction done
                    r_data_out   <= {DATA_WIDTH{1'b0}}; // Clear data
                    rresp_out_r  <= 2'b00; // Clear response
                    if (STARTRD) begin
                        rready <= 1'b1; // Assert RREADY to indicate ready to receive data
                    end
                end
                r_recv_s: begin
                    rready       <= 1'b1; // RREADY remains asserted until RVALID is high
                    r_idle       <= 1'b0; // Deassert idle status when receiving
                    if (RVALID && rready) begin // Check if slave has valid data and handshake completes
                        r_done       <= 1'b1; // Assert r_DONE for one cycle to indicate completion
                        r_data_out   <= RDATA; // Capture received data
                        rresp_out_r  <= RRESP; // Capture received response
                    end else begin
                        r_done       <= 1'b0; // Keep r_done deasserted if handshake not complete
                    end
                end
            endcase
        end
    end

endmodule
