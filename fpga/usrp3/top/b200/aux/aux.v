// AUX ADC data path

module aux #(
	parameter RADIO_FIFO_SIZE = 13,
	parameter DEVICE = "SPARTAN6"
) (
	input bus_clk,
	input bus_rst,

	input [63:0] i_tdata,
	input i_tlast,
	input i_tvalid,
	output i_tready,

	input radio_clk,
	input radio_rst,

	// For forcing into error state to keep in sync with other FIFO
	input [2:0] external_state,

	input strobe_rf,
	input [15:0] sample_div,
	input [3:0] spi_clk_div,

	output [63:0] debug,

	// Ouptut to DAC
	output dac_clk,
	output dac_sync,
	output dac_data
);

wire [63:0] i_tdata_r;
wire i_tlast_r, i_tready_r, i_tvalid_r;

axi_fifo_2clk #(.WIDTH(65), .SIZE(RADIO_FIFO_SIZE), .DEVICE(DEVICE)) aux_fifo
	(.reset(bus_rst),
	.i_aclk(bus_clk), .i_tvalid(i_tvalid), .i_tready(i_tready), .i_tdata({i_tlast, i_tdata}),
	.o_aclk(radio_clk), .o_tvalid(i_tvalid_r), .o_tready(i_tready_r), .o_tdata({i_tlast_r, i_tdata_r}));

wire [175:0] sample_tdata;
wire sample_tvalid, sample_tready;

new_tx_deframer aux_deframer
	(.clk(radio_clk), .reset(radio_rst), .clear(1'b0),
	.i_tdata(i_tdata_r), .i_tlast(i_tlast_r), .i_tvalid(i_tvalid_r), .i_tready(i_tready_r),
	.sample_tdata(sample_tdata), .sample_tvalid(sample_tvalid), .sample_tready(sample_tready),
	.debug());

wire [31:0] sample_aux;
reg strobe_aux;

aux_tx_control aux_control
	(.clk(radio_clk), .reset(radio_rst), .clear(1'b0),
	.external_state(external_state),
	.sample_tdata(sample_tdata), .sample_tvalid(sample_tvalid), .sample_tready(sample_tready),
	.sample(sample_aux), .run(), .strobe(strobe_aux),
	.debug(debug));

// Sample clock divider
reg [15:0] div_cnt;
always @(posedge radio_clk) begin
	strobe_aux <= 0;

	if(strobe_rf) begin
		div_cnt <= div_cnt + 1;
		if(div_cnt + 1 >= sample_div) begin
			div_cnt <= 0;
			strobe_aux <= 1;
		end
	end

	if(radio_rst) begin
		div_cnt <= 0;
		strobe_aux <= 0;
	end
end

// SPI transmit
aux_dac aux_dac_inst (
	.clk(radio_clk),
	.rst(radio_rst),

	.clk_div(spi_clk_div),

	.sample(sample_aux),
	.strobe(strobe_aux),

	.dac_clk(dac_clk),
	.dac_sync(dac_sync),
	.dac_data(dac_data)
);

endmodule
