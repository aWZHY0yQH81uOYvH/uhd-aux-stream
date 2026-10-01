// Output for DAC8552 16-bit serial DAC

module aux_dac (
	input clk,
	input rst,

	input [3:0] clk_div,

	input [31:0] sample,
	input strobe,

	output reg dac_clk,
	output reg dac_sync,
	output reg dac_data
);

reg [31:0] sample_reg;

reg [3:0] clk_div_cnt;
reg [3:0] state;
reg [4:0] shift_cnt;

localparam ST_WAIT  = 0;
localparam ST_DAC_A = 1;
localparam ST_FRAME = 2;
localparam ST_DAC_B = 3;

localparam BITS = 24;
wire [BITS-1:0] data_dac_a = {8'b00000000, sample_reg[15:0]};
wire [BITS-1:0] data_dac_b = {8'b00110100, sample_reg[31:16]}; // Update DAC registers at the same time
wire [BITS-1:0] data_dac = (state == ST_DAC_A ? data_dac_a : data_dac_b);

always @(posedge clk) begin
	if(strobe) begin
		sample_reg <= sample;
		if(state == ST_WAIT) begin
			state <= ST_DAC_A;
			shift_cnt <= BITS-1;
		end
	end

	clk_div_cnt <= clk_div_cnt + 1;
	if(clk_div_cnt + 1 == clk_div) begin
		clk_div_cnt <= 0;
		dac_clk <= !dac_clk;
		if(!dac_clk) begin // About to be rising edge
			case(state)
				ST_DAC_A, ST_DAC_B: begin
					dac_sync <= 0;
					dac_data <= data_dac[shift_cnt];
					shift_cnt <= shift_cnt - 1;
					if(shift_cnt == 0) begin
						shift_cnt <= BITS-1;
						state <= (state == ST_DAC_A ? ST_FRAME : ST_WAIT);
					end
				end

				ST_FRAME: begin
					state <= ST_DAC_B;
					dac_sync <= 1;
				end

				default: begin
					dac_sync <= 1;
				end
			endcase
		end
	end

	if(rst) begin
		dac_clk <= 0;
		dac_sync <= 1;
		dac_data <= 0;

		clk_div_cnt <= 0;
		state <= ST_WAIT;
	end
end

endmodule
