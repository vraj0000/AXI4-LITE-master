`timescale 1ns/1ps

module axi4_lite_master_interface #(
    parameter ADDR_WIDTH = 32, // Parameter for the address bus width
    parameter DATA_WIDTH = 32  // Parameter for the data bus width
)(
    // Master's input from CPU, GPU, NPU, DPU, ....
    input  wire                     STARTW,      // Start a Write transaction (from CPU)
    input  wire                     STARTR,      // Start a Read transaction (from CPU)

    input  wire [ADDR_WIDTH-1:0]    m_addr,      // Address for read/write from CPU
    input  wire [DATA_WIDTH-1:0]    m_wdata,     // Write data from CPU to subordinate

    // Master's output to CPU
    output wire [DATA_WIDTH-1:0]    m_rdata,     // Read data from subordinate to CPU
    output wire [1:0]               m_bresp,     // Write response from subordinate to CPU
    output wire [1:0]               m_rresp,     // Read response from subordinate to CPU
    output wire                     m_write_done, // Indicates if a write transaction is complete
    output wire                     m_read_done,  // Indicates if a read transaction is complete
    output wire                     m_idle        // Indicates if the entire master interface is idle

    // Global Signals
    ,input  wire                     ACLK        // Clock source
    ,input  wire                     ARESETN     // Global reset (active low)

    // AXI4-Lite Write Address Channel Signals (connected to subordinate)
    ,output wire  [ADDR_WIDTH-1:0]   AWADDR      // Write address
    ,output wire  [2:0]              AWPROT      // Protection type
    ,output wire                     AWVALID     // Write address valid
    ,input  wire                     AWREADY     // Write address ready

    // AXI4-Lite Write Data Channel Signals (connected to subordinate)
    ,output wire  [DATA_WIDTH-1:0]   WDATA       // Write data
    ,output wire  [(DATA_WIDTH/8)-1:0] WSTRB     // Write strobes
    ,output wire                     WVALID      // Write valid
    ,input  wire                     WREADY      // Write ready

    // AXI4-Lite Write Response Channel Signals (connected to subordinate)
    ,input  wire [1:0]               BRESP       // Write response
    ,input  wire                     BVALID      // Write response valid
    ,output wire                     BREADY      // Response ready

    // AXI4-Lite Read Address Channel Signals (connected to subordinate)
    ,output wire  [ADDR_WIDTH-1:0]   ARADDR      // Read address
    ,output wire  [2:0]              ARPROT      // Protection type
    ,output wire                     ARVALID     // Read address valid
    ,input  wire                     ARREADY     // Read address ready

    // AXI4-Lite Read Data Channel Signals (connected to subordinate)
    ,input  wire [DATA_WIDTH-1:0]    RDATA       // Read data
    ,input  wire [1:0]               RRESP       // Read response
    ,input  wire                     RVALID      // Read valid
    ,output wire                     RREADY      // Read ready
);

    // Internal wires to connect to instantiated channel modules
    wire aw_idle_chan;
    wire aw_done_chan;
    wire w_idle_chan;
    wire w_done_chan;
    wire b_idle_chan;
    wire b_done_chan;
    wire [1:0] bresp_out_chan;

    wire ar_idle_chan;
    wire ar_done_chan;
    wire r_idle_chan;
    wire r_done_chan;
    wire [DATA_WIDTH-1:0] rdata_out_chan;
    wire [1:0] rresp_out_chan;

    // Registers to control the start signals for each channel
    reg start_aw_reg;
    reg start_w_reg;
    reg start_b_reg;
    reg start_ar_reg;
    reg start_r_reg;

    // Registers to hold input data/address for channel modules
    reg [ADDR_WIDTH-1:0] wa_addr_reg;
    reg [DATA_WIDTH-1:0] iw_data_reg;
    reg [ADDR_WIDTH-1:0] ra_addr_reg;

    // Internal status registers for overall master state
    reg m_write_done_r;
    reg m_read_done_r;

    // Edge detection for start signals
    reg startw_prev, startr_prev;
    wire startw_posedge = STARTW & ~startw_prev;
    wire startr_posedge = STARTR & ~startr_prev;

    // Assign top-level outputs from internal registers/wires
    assign m_write_done = m_write_done_r;
    assign m_read_done  = m_read_done_r;
    assign m_idle       = (write_state == WRITE_IDLE) && (read_state == READ_IDLE);
    assign m_rdata      = rdata_out_chan;
    assign m_bresp      = bresp_out_chan;
    assign m_rresp      = rresp_out_chan;

    // --- Write Transaction FSM ---
    localparam WRITE_IDLE       = 2'b00; // Waiting for STARTW
    localparam WRITE_ADDR_DATA  = 2'b01; // Sending AW and W concurrently
    localparam WRITE_RESP       = 2'b10; // Waiting for B response

    reg [1:0] write_state, write_state_n;

    // Write FSM State Register
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            write_state <= WRITE_IDLE;
        end else begin
            write_state <= write_state_n;
        end
    end

    // Write FSM Next-State Logic (combinational)
    always @(*) begin
        write_state_n = write_state;

        case (write_state)
            WRITE_IDLE: begin
                if (startw_posedge) begin
                    write_state_n = WRITE_ADDR_DATA;
                end
            end
            WRITE_ADDR_DATA: begin
                if (aw_done_chan && w_done_chan) begin
                    write_state_n = WRITE_RESP;
                end
            end
            WRITE_RESP: begin
                if (b_done_chan) begin
                    write_state_n = WRITE_IDLE;
                end
            end
            default: write_state_n = WRITE_IDLE;
        endcase
    end

        // Write FSM Output Logic
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            start_aw_reg <= 1'b0;
            start_w_reg <= 1'b0;
            start_b_reg <= 1'b0;
            wa_addr_reg <= '0;
            iw_data_reg <= '0;
            m_write_done_r <= 1'b0;
            startw_prev <= 1'b0;
        end else begin
            startw_prev <= STARTW;
            
            // Default values
            start_aw_reg <= 1'b0;
            start_w_reg <= 1'b0;
            start_b_reg <= 1'b0;
            m_write_done_r <= 1'b0;

            case (write_state)
                WRITE_IDLE: begin
                    if (startw_posedge) begin
                        wa_addr_reg <= m_addr;
                        iw_data_reg <= m_wdata;
                    end
                end
                WRITE_ADDR_DATA: begin
                    start_aw_reg <= 1'b1;
                    start_w_reg <= 1'b1;
                end
                WRITE_RESP: begin
                    start_b_reg <= 1'b1;
                    if (b_done_chan) begin
                        m_write_done_r <= 1'b1;
                    end
                end
                default: begin  // ← ADD THIS
                    // Do nothing, use default values
                end
            endcase
        end
    end

    // --- Read Transaction FSM ---
    localparam READ_IDLE       = 2'b00; // Waiting for STARTR
    localparam READ_ADDR       = 2'b01; // Sending AR
    localparam READ_DATA       = 2'b10; // Waiting for R data

    reg [1:0] read_state, read_state_n;

    // Read FSM State Register
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            read_state <= READ_IDLE;
        end else begin
            read_state <= read_state_n;
        end
    end

    // Read FSM Next-State Logic (combinational)
    always @(*) begin
        read_state_n = read_state;

        case (read_state)
            READ_IDLE: begin
                if (startr_posedge) begin
                    read_state_n = READ_ADDR;
                end
            end
            READ_ADDR: begin
                if (ar_done_chan) begin
                    read_state_n = READ_DATA;
                end
            end
            READ_DATA: begin
                if (r_done_chan) begin
                    read_state_n = READ_IDLE;
                end
            end
            default: read_state_n = READ_IDLE;
        endcase
    end

    // Read FSM Output Logic  
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            start_ar_reg <= 1'b0;
            start_r_reg <= 1'b0;
            ra_addr_reg <= '0;
            m_read_done_r <= 1'b0;
            startr_prev <= 1'b0;
        end else begin
            startr_prev <= STARTR;
            
            // Default values
            start_ar_reg <= 1'b0;
            start_r_reg <= 1'b0;
            m_read_done_r <= 1'b0;

            case (read_state)
                READ_IDLE: begin
                    if (startr_posedge) begin
                        ra_addr_reg <= m_addr;
                    end
                end
                READ_ADDR: begin
                    start_ar_reg <= 1'b1;
                end
                READ_DATA: begin
                    start_r_reg <= 1'b1;
                    if (r_done_chan) begin
                        m_read_done_r <= 1'b1;
                    end
                end
                default: begin  // ← ADD THIS
                    // Do nothing, use default values  
                end
            endcase
        end
    end

    // Instantiate the Write Address Channel module
    axi4_write_address_channel #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) aw_channel_inst (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .STARTWA(start_aw_reg),
        .wa_addr(wa_addr_reg),
        .AWADDR(AWADDR),
        .AWPROT(AWPROT),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .aw_IDLE(aw_idle_chan),
        .aw_DONE(aw_done_chan)
    );

    // Instantiate the Write Data Channel module
    axi4_write_data_channel #(
        .DATA_WIDTH(DATA_WIDTH)
    ) w_channel_inst (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .STARTWA(start_w_reg),
        .iw_DATA(iw_data_reg),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .w_IDLE(w_idle_chan),
        .w_DONE(w_done_chan)
    );

    // Instantiate the Write Response Channel module
    axi4_write_response_channel b_channel_inst (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .STARTWR(start_b_reg),
        .BRESP(BRESP),
        .BVALID(BVALID),
        .BREADY(BREADY),
        .b_idle(b_idle_chan),
        .b_done(b_done_chan),
        .bresp_out(bresp_out_chan)
    );

    // Instantiate the Read Address Channel module
    axi4_read_address_channel #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) ar_channel_inst (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .STARTRA(start_ar_reg),
        .ra_addr(ra_addr_reg),
        .ARADDR(ARADDR),
        .ARPROT(ARPROT),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .ar_IDLE(ar_idle_chan),
        .ar_DONE(ar_done_chan)
    );

    // Instantiate the Read Data Channel module
    axi4_read_data_channel #(
        .DATA_WIDTH(DATA_WIDTH)
    ) r_channel_inst (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .STARTRD(start_r_reg),
        .RDATA(RDATA),
        .RRESP(RRESP),
        .RVALID(RVALID),
        .RREADY(RREADY),
        .r_IDLE(r_idle_chan),
        .r_DONE(r_done_chan),
        .r_DATA_out(rdata_out_chan),
        .rresp_out(rresp_out_chan)
    );

endmodule