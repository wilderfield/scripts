# linux-syslog.tcl
#
# Author: Rob Armstrong, Xilinx, Inc.
#
# 2015 (c) Xilinx, Inc. This file is licensed uner the terms of the GNU
# General Public License version 2. This program is licensed "as is"
# without any warranty of any kind, whether express or implied.
# 
# This is a utility script for the Xilinx System Debugger (XSDB) that
# allows text dumping of the Linux kernel log buffer via memory peek/poke operations.
# It is current as of PetaLinux release 2015.2 (or Xilinx Github kernel tag
# xilinx-v2015.2.1).
#
# When using newer software, XSDB is preferred over XMD.
#
# Usage:
#
#  Determine the location of the Linux system log buffer in memory. Typically, this can be
#  found in the file System.map generated in the Linux kernel build directory. For Xilinx
#  PetaLinux projects, this will be under build/linux/kernel/<kernel_name>/System.map. Grep
#  the file for __log_buf.
#
#  Usage within XSDB is as follows:
#   % source linux-syslog.tcl
#   % syslog <__log_buf address>
#
#   e.g.
#   % syslog 0x40900000
#

proc linux_mem_read { address } {
    return [mrd -value $address]
}

proc linux_mem_read_text { address length } {
    return [mrd -value -bin -size b $address $length]
}

proc syslog { bufaddr } {
    set addr $bufaddr

    while {1} {
	set startaddr $addr
	
	set ts_nsec_low [linux_mem_read $addr]
	incr addr 4
	set ts_nsec_high [linux_mem_read $addr]
	incr addr 4
	set ts_nsec [expr {[expr {$ts_nsec_high << 32}] + $ts_nsec_low}]

	set mval [linux_mem_read $addr]
	set text_len [expr {[expr {$mval >> 16}] & 0xffff}]
	set len [expr {$mval & 0xffff}]
	incr addr 4

	# The following are currently unused, but could be used to filter
        # by log level, etc.
	
        # set mval [linux_mem_read $addr]  
        # set dict_len [expr {$mval & 0xffff}]
        # set facility [expr {[expr {$mval >> 16}] & 0xff}]
        # set flags [expr {[expr {$mval >> 24}] & 0x1f}]
        # set level [expr {[expr $mval >> 28] & 0x07}]
	incr addr 4

	if {$len == 0} {
	    return
	}
        
        # Uncomment below to display a timestamp before the message
        # puts -nonewline "$ts_nsec: "
        
	puts [linux_mem_read_text $addr $text_len]
	
        set addr [expr {$startaddr + $len}]
    }
}
