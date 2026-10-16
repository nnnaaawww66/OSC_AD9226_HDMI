# Hardware ENABLE_RATE_SWITCH=0 enforces 10MSa/s. Higher rates are unqualified and rejected by RTL.
# AD9226 tOD3.5..7ns + provisional external round-trip allowance0..3ns.
create_generated_clock -name adc_fwd10 -source [get_pins clocks/adc_mmcm/CLKOUT1] -divide_by 1 [get_ports adc_clk]
set_input_delay -clock adc_fwd10 -max 10.000 [get_ports {adc_data[*] adc_otr}]
set_input_delay -clock adc_fwd10 -min 3.500 [get_ports {adc_data[*] adc_otr}]
