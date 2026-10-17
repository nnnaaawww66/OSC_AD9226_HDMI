# Toggle mailbox control: exclude only the first metastability synchronizer stage.
set_false_path -to [get_cells -hier -filter {NAME =~ */req_meta_reg || NAME =~ */ack_meta_reg}]
# A request crosses two destination flops before bundled data is captured; source holds data through ACK.
# 10ns is at most one destination period (the fastest destination is 100MHz).
set_max_delay -datapath_only 10.000 -from [get_cells -hier -filter {NAME =~ */hold_data_reg*}] -to [get_cells -hier -filter {NAME =~ */ddata_reg*}]
# Video metadata is held until an ACK that is only issued at the vertical blank boundary.
set_max_delay -datapath_only 10.000 -from [get_cells -hier -filter {NAME =~ */display/meta_hold_reg*}] -to [get_cells -hier -filter {NAME =~ */display/meta_pix_reg*}]

set_false_path -to [get_pins -of_objects [get_cells -hier -filter {ASYNC_REG == TRUE}] -filter {REF_PIN_NAME == PRE || REF_PIN_NAME == CLR}]

# UG472 BUFGMUX_CTRL S inputs permit asynchronous glitch-free selection.
set_false_path -to [get_pins -of_objects [get_cells -hier -filter {NAME =~ clocks/* && REF_NAME == BUFGCTRL}] -filter {REF_PIN_NAME == S0 || REF_PIN_NAME == S1}]
