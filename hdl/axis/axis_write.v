/**
 * Module:
 *  axis_write
 *
 * Description:
 *  The axis_write takes a system stream an translate it to the axi data
 *  channel protocol.
 *
 * Test bench:
 *  axis_write_tb.v
 *
 * Created:
 *  Tue Nov  4 22:18:14 EST 2014
 *
 * Author:
 *  Berin Martini (berin.martini@gmail.com)
 */
`ifndef _axis_write_ `define _axis_write_


`include "axis_addr.v"
`include "axis_write_data.v"

module axis_write
  #(parameter
    BUF_AWIDTH      = 9,

    CONFIG_ID       = 1,
    CONFIG_ADDR     = 23,
    CONFIG_DATA     = 24,
    CONFIG_AWIDTH   = 5,
    CONFIG_DWIDTH   = 32,

    AXI_LEN_WIDTH   = 8,
    AXI_ADDR_WIDTH  = 32,
    AXI_DATA_WIDTH  = 32,
    DATA_WIDTH      = 32)
   (input                               clk,
    input                               rst,

    input       [CONFIG_AWIDTH-1:0]     cfg_addr,
    input       [CONFIG_DWIDTH-1:0]     cfg_data,
    input                               cfg_valid,

    input                               axi_awready,
    output      [AXI_ADDR_WIDTH-1:0]    axi_awaddr,
    output      [AXI_LEN_WIDTH-1:0]     axi_awlen,
    output                              axi_awvalid,

    output                              axi_wlast,
    output      [AXI_DATA_WIDTH-1:0]    axi_wdata,
    output                              axi_wvalid,
    input                               axi_wready,

    input       [DATA_WIDTH-1:0]        data,
    input                               valid,
    output                              ready
);

    /**
     * Local parameters
     */

    localparam WIDTH_RATIO  = AXI_DATA_WIDTH/DATA_WIDTH;
    localparam CONFIG_NB    = 2;
    localparam STORE_WIDTH  = CONFIG_DWIDTH*CONFIG_NB;

    localparam
        C_IDLE      = 0,
        C_CONFIG    = 1,
        C_WAIT      = 2,
        C_ENABLE    = 3;


`ifdef VERBOSE
    initial $display("\using 'axis_write'\n");
`endif


    /**
     * Internal signals
     */


    reg  [3:0]                          c_state;
    reg  [3:0]                          c_state_nx;

    wire                                cfg_addr_ready;
    wire                                cfg_data_ready;

    reg  [CONFIG_AWIDTH-1:0]            cfg_addr_r;
    reg  [CONFIG_DWIDTH-1:0]            cfg_data_r;
    reg                                 cfg_valid_r;
    wire [STORE_WIDTH+CONFIG_DWIDTH-1:0]    cfg_store_i;
    reg  [STORE_WIDTH-1:0]              cfg_store;
    reg  [7:0]                          cfg_cnt;

    wire [CONFIG_DWIDTH-1:0]            start_addr;
    reg  [CONFIG_DWIDTH-1:0]            cfg_address;
    wire [CONFIG_DWIDTH-1:0]            str_length;
    reg  [CONFIG_DWIDTH-1:0]            cfg_length;
    reg                                 cfg_enable;
    wire                                id_valid;
    wire                                addressed;
    wire                                axis_data;


    /**
     * Implementation
     */

    assign cfg_store_i  = {cfg_store, cfg_data_r};

    assign start_addr   = cfg_store[CONFIG_DWIDTH +: CONFIG_DWIDTH];

    assign str_length   = cfg_store[0 +: CONFIG_DWIDTH];

    assign id_valid     = (CONFIG_ID == cfg_data_r);

    assign addressed    = (CONFIG_ADDR == cfg_addr_r) & cfg_valid_r;

    assign axis_data    = (CONFIG_DATA == cfg_addr_r) & cfg_valid_r;


    // register for improved timing
    always @(posedge clk)
        if (rst)    cfg_valid_r <= 1'b0;
        else        cfg_valid_r <= cfg_valid;


    // register for improved timing
    always @(posedge clk) begin
        cfg_addr_r <= cfg_addr;
        cfg_data_r <= cfg_data;
    end


    always @(posedge clk)
        if (c_state[C_CONFIG] & axis_data) begin
            cfg_store <= cfg_store_i[0 +: STORE_WIDTH];
        end


    always @(posedge clk) begin
        cfg_cnt <= 'b0;

        if (c_state[C_CONFIG]) begin
            cfg_cnt <= cfg_cnt + {7'b0, axis_data};
        end
    end


    always @(posedge clk)
        if (rst)    cfg_enable <= 1'b0;
        else        cfg_enable <= c_state[C_ENABLE];


    always @(posedge clk) begin
        if (c_state[C_ENABLE]) begin
            cfg_address <= start_addr;
            cfg_length  <= str_length;
        end
    end


    always @(posedge clk)
        if (rst) begin
            c_state         <= 'b0;
            c_state[C_IDLE] <= 1'b1;
        end
        else c_state <= c_state_nx;


    always @* begin : CONFIG_
        c_state_nx = 'b0;

        case (1'b1)
            c_state[C_IDLE] : begin
                if (addressed & id_valid) begin
                    c_state_nx[C_CONFIG] = 1'b1;
                end
                else c_state_nx[C_IDLE] = 1'b1;
            end
            c_state[C_CONFIG] : begin
                if (axis_data & ((CONFIG_NB-1) <= cfg_cnt)) begin
                    c_state_nx[C_WAIT] = 1'b1;
                end
                else c_state_nx[C_CONFIG] = 1'b1;
            end
            c_state[C_WAIT] : begin
                if (cfg_addr_ready & cfg_data_ready) begin
                    c_state_nx[C_ENABLE] = 1'b1;
                end
                else c_state_nx[C_WAIT] = 1'b1;
            end
            c_state[C_ENABLE] : begin
                c_state_nx[C_IDLE] = 1'b1;
            end
            default : begin
                c_state_nx[C_IDLE] = 1'b1;
            end
        endcase
    end


    axis_addr #(
        .CONFIG_DWIDTH  (CONFIG_DWIDTH),
        .WIDTH_RATIO    (WIDTH_RATIO),
        .CONVERT_SHIFT  ($clog2(WIDTH_RATIO)),
        .AXI_LEN_WIDTH  (AXI_LEN_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH))
    axis_addr_ (
        .clk            (clk),
        .rst            (rst),

        .cfg_address    (cfg_address),
        .cfg_length     (cfg_length),
        .cfg_valid      (cfg_enable),
        .cfg_ready      (cfg_addr_ready),

        .axi_aready     (axi_awready),
        .axi_aaddr      (axi_awaddr),
        .axi_alen       (axi_awlen),
        .axi_avalid     (axi_awvalid)
    );


    axis_write_data #(
        .BUF_AWIDTH     (BUF_AWIDTH),
        .CONFIG_DWIDTH  (CONFIG_DWIDTH),
        .WIDTH_RATIO    (WIDTH_RATIO),
        .CONVERT_SHIFT  ($clog2(WIDTH_RATIO)),
        .AXI_LEN_WIDTH  (AXI_LEN_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH))
    axis_write_data_ (
        .clk            (clk),
        .rst            (rst),

        .cfg_length     (cfg_length),
        .cfg_valid      (cfg_enable),
        .cfg_ready      (cfg_data_ready),

        .axi_wlast      (axi_wlast),
        .axi_wdata      (axi_wdata),
        .axi_wvalid     (axi_wvalid),
        .axi_wready     (axi_wready),

        .data           (data),
        .valid          (valid),
        .ready          (ready)
    );



endmodule

`endif //  `ifndef _axis_write_
