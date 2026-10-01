#include <uhd/usrp/multi_usrp.hpp>
#include <cmath>
#include <complex>
#include <vector>
#include <cstdio>

int main() {
	auto usrp = uhd::usrp::multi_usrp::make("type=b200,enable_user_regs,fpga=/tmp/b210.bin,send_frame_size=16360,num_send_frames=128");

	// RF settings
	usrp->set_tx_rate(10e6);
	usrp->set_tx_gain(40);
	usrp->set_tx_freq(50e6);

	// Set sample rate divison
	auto regs = usrp->get_user_settings_iface(0);
	const int rf2aux = 128; // Division between RF samples and AUX samples
	regs->poke32(0, rf2aux);

	// Set SPI clock speed
	const double rf_clk = usrp->get_master_clock_rate();
	int spi_clk_div = 1;
	double spi_clk = rf_clk / (spi_clk_div * 2);
	while(spi_clk > 30e6) {
		spi_clk_div++;
		spi_clk = rf_clk / (spi_clk_div * 2);
	}

	regs->poke32(4, spi_clk_div);

	printf("RF  clock: %4g MHz\n", rf_clk / 1e6);
	printf("AUX clock: %4g MHz\n", spi_clk / 1e6);

	// Get streams
	uhd::stream_args_t rf_args("fc32", "sc16");
	rf_args.channels = {0};
	auto rf = usrp->get_tx_stream(rf_args);

	uhd::stream_args_t aux_args("sc16", "sc16");
	aux_args.channels = {2};
	auto aux = usrp->get_device()->get_tx_stream(aux_args); // Need get_device() to get the raw stream

	// Packet size can't be too large otherwise it fragments and can violate the strict AUX then RF
	// ordering required to maintain alignment under underrun conditions
	const size_t max_spp = rf->get_max_num_samps();
	const size_t max_spp_round = (max_spp / rf2aux) * rf2aux; // Round to lowest multiple of AUX samples
	std::vector<std::complex<float>> rf_buf(max_spp_round);
	std::vector<std::complex<uint16_t>> aux_buf(rf_buf.size() / rf2aux);

	// Test data
	for(size_t i = 0; i < rf_buf.size()/2; i++)
		rf_buf[i] = {(float)i / rf_buf.size() + 0.5f, 0};
	
	for(size_t i = 0; i < aux_buf.size()/2; i++) {
		float x = (float)i / aux_buf.size();
		aux_buf[i] = std::complex<uint16_t>(x * 0xFFFF, (1-x) * 0xFFFF);
	}

	uhd::tx_metadata_t md;
	while(true) {
		// AUX must be sent first to fill its FIFO before RX starts sampling
		aux->send(aux_buf.data(), aux_buf.size(), md);
		rf->send(rf_buf.data(), rf_buf.size(), md);

		// Debug register
		// std::cout << std::format("{:08X}\n", regs->peek64(0));
	}
}
