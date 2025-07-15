`timescale 1ns/1ps

module axi4_read_address_channel #(
    parameter ADDR_WIDTH = 32 // Parameter for the address bus width
) (
    // Global Signals
    input  wire                   ACLK,      // Clock source
    input  wire                   ARESETN,   // Global reset (active low)

    // Master-side Control and Data Inputs
    input  wire                   STARTRA,   // Signal to start a Read Address transaction
    input  wire [ADDR_WIDTH-1:0]  ra_addr,   // Read address from the master

    // AXI4-Lite Read Address Channel Interface (Master outputs/Slave inputs)
    output wire [ADDR_WIDTH-1:0]  ARADDR,    // Read address output to subordinate
    output wire [2:0]             ARPROT,    // Protection type output to subordinate
    output wire                   ARVALID,   // Read address valid output to subordinate
    input  wire                   ARREADY,   // Read address ready input from subordinate

    // Status Outputs for Top Module
    output wire                   ar_IDLE,   // Indicates if the AR channel is idle
    output wire                   ar_DONE    // Indicates if the AR transaction is complete
);

    // Internal registers for AXI4 outputs
    reg  [ADDR_WIDTH-1:0]         araddr;
    reg  [2:0]                    arprot;
    reg                           arvalid;

    // Internal status registers
    reg                           ar_idle;
    reg                           ar_done;

    // Assign outputs from internal registers
    assign ARADDR  = araddr;
    assign ARPROT  = arprot;
    assign ARVALID = arvalid;

    assign ar_IDLE = ar_idle;
    assign ar_DONE = ar_done;

    // State parameters for the FSM
    localparam ar_idle_s = 1'b0; // Idle state: waiting for a transaction request
    localparam ar_send_s = 1'b1; // Send state: asserting ARVALID and waiting for ARREADY

    reg state, state_n; // Current and next state registers

    // State register (FSM sequential logic)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN)
            state <= ar_idle_s; // Reset to idle state
        else
            state <= state_n;   // Update state on clock edge
    end

    // Next-state logic (FSM combinational logic)
    always @(*) begin
        state_n = state; // Default: stay in current state
        case (state)
            ar_idle_s: if (STARTRA) state_n = ar_send_s;
            ar_send_s: if (ARREADY && arvalid) state_n = ar_idle_s;
        endcase
    end

    // Output registers (Sequential logic for AXI4 signals and status)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            // Reset all outputs to their default inactive states
            araddr  <= {ADDR_WIDTH{1'b0}};
            arprot  <= 3'b000;
            arvalid <= 1'b0;
            ar_idle <= 1'b1; // Initially idle
            ar_done <= 1'b0; // No transaction done
        end else begin
            case (state)
                ar_idle_s: begin
                    arvalid <= 1'b0; // Deassert ARVALID when idle
                    ar_idle <= 1'b1; // Assert idle status
                    ar_done <= 1'b0; // No transaction done
                    if (STARTRA) begin
                        // Load address and protection, assert ARVALID to start transaction
                        araddr  <= ra_addr;
                        arprot  <= 3'b000; // Assuming fixed protection for AXI4-Lite
                        arvalid <= 1'b1;   // Assert ARVALID
                    end
                end
                ar_send_s: begin
                    arvalid <= 1'b1; // ARVALID remains asserted until ARREADY is high
                    ar_idle <= 1'b0; // Deassert idle status when sending
                    if (ARREADY && arvalid) begin // Check for handshake completion
                        ar_done <= 1'b1; // Assert ar_DONE for one cycle to indicate completion
                    end else begin
                        ar_done <= 1'b0; // Keep ar_done deasserted if handshake not complete
                    end
                end
            endcase
        end
    end

endmodule
