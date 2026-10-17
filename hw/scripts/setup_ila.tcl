foreach {name width} {scope_ila_adc 128 scope_ila_sys 128 scope_ila_video 64} {
    if {![llength [get_ips -quiet $name]]} {
        create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name $name
    }
    set_property -dict [list CONFIG.C_NUM_OF_PROBES 1 CONFIG.C_PROBE0_WIDTH $width CONFIG.C_DATA_DEPTH 1024 CONFIG.C_EN_STRG_QUAL 0 CONFIG.C_TRIGIN_EN false CONFIG.C_TRIGOUT_EN false] [get_ips $name]
    set_property generate_synth_checkpoint false [get_files */$name.xci]
    generate_target all [get_ips $name]
}
