`timescale 1ns/1ps

module axi4_write_data_channel #(
    parameter DATA_WIDTH = 32 // Parameter for the data bus width
) (
    // Global
    input  wire                   ACLK,
    input  wire                   ARESETN,

    // Master-side inputs for starting a write
    // Note: STARTWA is used here as it's driven by the top-level master FSM
    // which starts both AW and W channels concurrently for AXI4-Lite.
    input  wire                   STARTWA,
    input  wire [DATA_WIDTH-1:0]  iw_DATA,

    // AXI4 Write Data Channel Interface (Master outputs/Slave inputs)
    output wire [DATA_WIDTH-1:0]  WDATA,
    output wire [(DATA_WIDTH/8)-1:0] WSTRB,
    output wire                   WVALID,
    input  wire                   WREADY, // AXI4 input from slave

    // Status
    output wire                   w_IDLE,
    output wire                   w_DONE
);

    // Internal registers for AXI4 outputs
    reg  [DATA_WIDTH-1:0]         wdata_r;
    reg  [(DATA_WIDTH/8)-1:0]     wstrb_r;
    reg                           wvalid_r;

    // Internal status registers
    reg                           w_idle_r; // Renamed for consistency
    reg                           w_done_r;

    // Assign outputs from internal registers
    assign WDATA  = wdata_r;
    assign WSTRB  = wstrb_r;
    assign WVALID = wvalid_r;

    assign w_IDLE = w_idle_r;
    assign w_DONE = w_done_r;

    // State parameters
    localparam w_idle_s = 1'b0; // Idle state: waiting for STARTWA
    localparam w_send_s = 1'b1; // Send state: asserting WVALID and waiting for WREADY

    reg state, state_n;

    // State register (FSM sequential logic)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) 
            state <= w_idle_s;
        else          
            state <= state_n;
    end

    // Next-state logic (FSM combinational logic)
    always @(*) begin
        state_n = state;
        w_idle_r = 1'b0; // Default deassert w_idle_r

        case (state)
            w_idle_s: begin
                w_idle_r = 1'b1; // Assert w_idle_r when in idle state
                if (STARTWA) state_n = w_send_s;
            end
            w_send_s: begin
                // Transition back to idle when the handshake (WVALID && WREADY) completes
                if (WREADY && wvalid_r) state_n = w_idle_s;
            end
        endcase
    end

    // Output registers (Sequential logic for AXI4 signals and status)
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            wdata_r  <= {DATA_WIDTH{1'b0}};
            wstrb_r  <= {(DATA_WIDTH/8){1'b0}};
            wvalid_r <= 1'b0;
            w_done_r <= 1'b0;
        end else begin
            w_done_r <= 1'b0; // Default to 0 unless transaction completes

            case (state)
                w_idle_s: begin
                    wvalid_r <= 1'b0; // Deassert WVALID when idle
                    if (STARTWA) begin
                        wdata_r  <= iw_DATA; // Load write data
                        wstrb_r  <= {(DATA_WIDTH/8){1'b1}}; // All strobes high for a full data transfer
                        wvalid_r <= 1'b1; // Assert WVALID to indicate valid data
                    end
                end
                w_send_s: begin 
                    // WVALID remains asserted until WREADY is high
                    if (WREADY && wvalid_r) begin
                        wvalid_r <= 1'b0; // Deassert WVALID after handshake
                        w_done_r <= 1'b1; // Assert w_DONE for one cycle after handshake
                    end else begin
                        wvalid_r <= 1'b1; // Keep WVALID asserted if handshake not complete
                    end
                end
            endcase
        end
    end

endmodule
