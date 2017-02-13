
################################################################
# This script adds a submodule to a design targeting a compatible
# Xilinx FPGA (tested with Zynq-7000 and Zynq UltraScale+) containing
# a test pattern generator IP along with video DMA blocks, etc.
#
# The constructed system is a V4L2 compatible video test pattern
# source for use in video systems targeting Xilinx FPGAs.
#
# To run this script, run the following commands from Vivado Tcl console:
# source add_tpg_subsystem.tcl
#
# Note that you must have an existing project and an existing, opened
# IPI block diagram.
#
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2016.4
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
    common::send_msg_id "BD_TCL-1002" "WARNING" "This script was last tested in Vivado <$scripts_vivado_version>. You are running <$current_vivado_version>. There may be differences in the underlying IP that result in incorrect behavior. Please verify all IP configurations and connections. You have been warned!"

}

################################################################
# START
################################################################

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
    puts "ERROR: This script must be called from an open Vivado project."
    return -1;
}

# Ensure that we have an existing, open design
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${cur_design} ne ""} {
    # This script will naively add the TPG instance to the currently open BD
    # design.

    common::send_msg_id "BD_TCL-002" "INFO" "Constructing design in IPI design <$cur_design>..."
} else {
    set nRet 1
    set errMsg "You must have an open BD design to call this script"
}

if { $nRet != 0 } {
    catch {common::send_msg_id "BD_TCL-114" "ERROR" $errMsg}
    return $nRet
}

##################################################################
# DESIGN PROCs
##################################################################

# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  set hier_obj [create_bd_cell -type hier "tpg_in"]
  current_bd_instance $hier_obj


  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_s2mm_vdma
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_vdma_ctrl
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_vtc_ctrl
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_tpg_ctrl

  # Create pins
  create_bd_pin -dir I -type clk vid_sys_clk
  create_bd_pin -dir I -type rst tpg_reset_n
  create_bd_pin -dir I -type rst vid_sys_clk_rst_n
  create_bd_pin -dir I -type clk vid_clk
  create_bd_pin -dir O -type intr irq_tpg
  create_bd_pin -dir O -type intr irq_vtc
  create_bd_pin -dir O -type intr irq_vdma_s2mm
  create_bd_pin -dir I -type clk sys_clk
  create_bd_pin -dir I -type rst sys_clk_rst_n

  # Create instance: vdma, and set properties
  set vdma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma vdma ]
  set_property -dict [ list \
                           CONFIG.c_include_mm2s {0} \
                           CONFIG.c_mm2s_genlock_mode {0} \
                           CONFIG.c_num_fstores {1} \
                           CONFIG.c_s2mm_linebuffer_depth {2048} \
                           CONFIG.c_s2mm_max_burst_length {16} \
                          ] $vdma

  # Create instance: video_bus_slice, and set properties
  set video_bus_slice [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter video_bus_slice ]
  set_property -dict [ list \
                           CONFIG.M_TDATA_NUM_BYTES {2} \
                           CONFIG.S_TDATA_NUM_BYTES {3} \
                           CONFIG.TDATA_REMAP {tdata[15:0]} \
                          ] $video_bus_slice

  # Create instance: constant_24_0, and set properties
  set constant_24_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant constant_24_0 ]
  set_property -dict [ list \
                           CONFIG.CONST_VAL {0} \
                           CONFIG.CONST_WIDTH {24} \
                          ] $constant_24_0

  # Create instance: vtc, and set properties
  set vtc [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc vtc ]
  set_property -dict [ list \
                           CONFIG.GEN_F0_VBLANK_HEND {1920} \
                           CONFIG.GEN_F0_VBLANK_HSTART {1920} \
                           CONFIG.GEN_F0_VFRAME_SIZE {1125} \
                           CONFIG.GEN_F0_VSYNC_HEND {1920} \
                           CONFIG.GEN_F0_VSYNC_HSTART {1920} \
                           CONFIG.GEN_F0_VSYNC_VEND {1088} \
                           CONFIG.GEN_F0_VSYNC_VSTART {1083} \
                           CONFIG.GEN_F1_VBLANK_HEND {1920} \
                           CONFIG.GEN_F1_VBLANK_HSTART {1920} \
                           CONFIG.GEN_F1_VFRAME_SIZE {1125} \
                           CONFIG.GEN_F1_VSYNC_HEND {1920} \
                           CONFIG.GEN_F1_VSYNC_HSTART {1920} \
                           CONFIG.GEN_F1_VSYNC_VEND {1088} \
                           CONFIG.GEN_F1_VSYNC_VSTART {1083} \
                           CONFIG.GEN_HACTIVE_SIZE {1920} \
                           CONFIG.GEN_HFRAME_SIZE {2200} \
                           CONFIG.GEN_HSYNC_END {2052} \
                           CONFIG.GEN_HSYNC_START {2008} \
                           CONFIG.GEN_VACTIVE_SIZE {1080} \
                           CONFIG.VIDEO_MODE {1080p} \
                           CONFIG.enable_detection {false} \
                          ] $vtc

  # Create instance: tpg, and set properties
  set tpg [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_tpg tpg ]
  set_property -dict [ list \
                           CONFIG.HAS_AXI4S_SLAVE {1} \
                          ] $tpg

  # Create instance: vid_in_axi4s, and set properties
  set vid_in_axi4s [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s vid_in_axi4s ]
  set_property -dict [ list \
                           CONFIG.C_ADDR_WIDTH {5} \
                           CONFIG.C_HAS_ASYNC_CLK {1} \
                          ] $vid_in_axi4s

  # Create interface connections
  connect_bd_intf_net -intf_net vdma_M_AXI_S2MM [get_bd_intf_pins m_axi_s2mm_vdma] [get_bd_intf_pins vdma/M_AXI_S2MM]
  connect_bd_intf_net -intf_net video_bus_slice_M_AXIS [get_bd_intf_pins vdma/S_AXIS_S2MM] [get_bd_intf_pins video_bus_slice/M_AXIS]
  connect_bd_intf_net -intf_net tpg_m_axis_video [get_bd_intf_pins video_bus_slice/S_AXIS] [get_bd_intf_pins tpg/m_axis_video]
  connect_bd_intf_net -intf_net vid_in_axi4s_video_out [get_bd_intf_pins tpg/s_axis_video] [get_bd_intf_pins vid_in_axi4s/video_out]
  connect_bd_intf_net -intf_net M00_AXI [get_bd_intf_pins s_axi_tpg_ctrl] [get_bd_intf_pins tpg/s_axi_CTRL]
  connect_bd_intf_net -intf_net M01_AXI [get_bd_intf_pins s_axi_vtc_ctrl] [get_bd_intf_pins vtc/ctrl]
  connect_bd_intf_net -intf_net M02_AXI [get_bd_intf_pins s_axi_vdma_ctrl] [get_bd_intf_pins vdma/S_AXI_LITE]

  # Create port connections
  connect_bd_net -net vdma_s2mm_introut [get_bd_pins irq_vdma_s2mm] [get_bd_pins vdma/s2mm_introut]
  connect_bd_net -net constant_24_0_dout [get_bd_pins constant_24_0/dout] [get_bd_pins vid_in_axi4s/vid_data]
  connect_bd_net -net sys_clk_rst_n [get_bd_pins sys_clk_rst_n] [get_bd_pins vdma/axi_resetn] [get_bd_pins vtc/s_axi_aresetn]
  connect_bd_net -net vid_sys_clk_rst_n [get_bd_pins vid_sys_clk_rst_n] [get_bd_pins video_bus_slice/aresetn]
  connect_bd_net -net tpg_reset_n [get_bd_pins tpg_reset_n] [get_bd_pins tpg/ap_rst_n]
  connect_bd_net -net vid_clk [get_bd_pins vid_clk] [get_bd_pins vtc/clk] [get_bd_pins vid_in_axi4s/vid_io_in_clk]
  connect_bd_net -net vtc_active_video_out [get_bd_pins vtc/active_video_out] [get_bd_pins vid_in_axi4s/vid_active_video]
  connect_bd_net -net vtc_hblank_out [get_bd_pins vtc/hblank_out] [get_bd_pins vid_in_axi4s/vid_hblank]
  connect_bd_net -net vtc_hsync_out [get_bd_pins vtc/hsync_out] [get_bd_pins vid_in_axi4s/vid_hsync]
  connect_bd_net -net vtc_irq [get_bd_pins irq_vtc] [get_bd_pins vtc/irq]
  connect_bd_net -net vtc_vblank_out [get_bd_pins vtc/vblank_out] [get_bd_pins vid_in_axi4s/vid_vblank]
  connect_bd_net -net vtc_vsync_out [get_bd_pins vtc/vsync_out] [get_bd_pins vid_in_axi4s/vid_vsync]
  connect_bd_net -net tpg_interrupt [get_bd_pins irq_tpg] [get_bd_pins tpg/interrupt]
  connect_bd_net -net sys_clk [get_bd_pins sys_clk] [get_bd_pins vdma/s_axi_lite_aclk] [get_bd_pins vtc/s_axi_aclk]
  connect_bd_net -net vid_sys_clk [get_bd_pins vid_sys_clk] [get_bd_pins vdma/m_axi_s2mm_aclk] [get_bd_pins vdma/s_axis_s2mm_aclk] [get_bd_pins video_bus_slice/aclk] [get_bd_pins tpg/ap_clk] [get_bd_pins vid_in_axi4s/aclk]

  # Restore current instance
  current_bd_instance $oldCurInst

  # Create instance: tpg_reset_slice, and set properties
  set tpg_reset_slice [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice tpg_reset_slice ]
  set_property -dict [ list \
                           CONFIG.DIN_FROM {0} \
                           CONFIG.DIN_TO {0} \
                           CONFIG.DIN_WIDTH {95} \
                          ] $tpg_reset_slice

  # Connect TPG reset slice dout to TPG reset isntance
  connect_bd_net -net tpg_reset_n [get_bd_pins tpg_in/tpg_reset_n] [get_bd_pins tpg_reset_slice/Dout]
  
  save_bd_design

}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


