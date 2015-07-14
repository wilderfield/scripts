# linux-syslog.tcl
# 
# Author: Rob Armstrong, Xilinx, Inc.
# 
# 2014 (c) Xilinx, Inc. This file is licensed uner the terms of the GNU
# General Public License version 2. This program is licensed "as is"
# without any warranty of any kind, whether express or implied.
# 
# This is a utility script for the Xilinx Microprocessor Debugger (XMD) that
# allows text dumping of the Linux kernel log buffer via memory peek/poke operations.
# It is current as of PetaLinux release 2013.10.
# 
# TODO:
# 1. Enable more interesting filtering of log buffer messages (filter by message level, etc)
#
# 2. Enable more coherent time stamping
# 


proc linux_mem_read { address } {
    return 0x[ string range [mrd $address 1 w] 12 19]
}

proc logmsg_flags { bufaddr } {
    set startaddr $bufaddr
    
    set ts_nsec_low [linux_mem_read $startaddr]
    incr startaddr 4
    set ts_nsec_high [linux_mem_read $startaddr]
    incr startaddr 4
    set ts_nsec [expr [expr $ts_nsec_high << 32] + $ts_nsec_low]
    
    set mval [linux_mem_read $startaddr]
    set text_len [expr [expr $mval >> 16] & 0xffff]
    set len [expr $mval & 0xffff]
    incr startaddr 4
    
    set mval [linux_mem_read $startaddr]  
    set dict_len [expr $mval & 0xffff]
    set facility [expr [expr $mval >> 16] & 0xff]
    set flags [expr [expr $mval >> 24] & 0x1f]
    set level [expr [expr $mval >> 28] & 0x07]
    
    puts "Message at $bufaddr:"
    puts "  Occurs at time: $ts_nsec"
    puts "  Length:         $len"
    puts "  Text Length:    $text_len"
    puts "  Dict. Length:   $dict_len"
    puts "  Flags           $flags"
    puts "  Level:          $level"
    
    incr startaddr 4
    set endaddr [expr $startaddr + $text_len]
    
    while {$startaddr < $endaddr} {
        set mval [linux_mem_read $startaddr]
        set shift 0
        
        while {$shift <= 24} {
            set char [expr [expr $mval >> $shift] & 0xff]
            incr shift 8
            set text_char [format "%c" $char]
            puts -nonewline "$text_char"
        }
        
        incr startaddr 4
    }
    
    puts ""
}
    
proc syslog { bufaddr } {
    set addr $bufaddr
    
    while {1} {
        
        set startaddr $addr
        set ts_nsec_low [linux_mem_read $addr]
        incr addr 4
        set ts_nsec_high [linux_mem_read $addr]
        incr addr 4
        set ts_nsec [expr [expr $ts_nsec_high << 32] + $ts_nsec_low]
        
        set mval [linux_mem_read $addr]
        set text_len [expr [expr $mval >> 16] & 0xffff]
        set len [expr $mval & 0xffff]
        incr addr 4
        
        # The following are currently unused, but could be used to filter
        # by log level, etc.
        set mval [linux_mem_read $addr]  
        set dict_len [expr $mval & 0xffff]
        set facility [expr [expr $mval >> 16] & 0xff]
        set flags [expr [expr $mval >> 24] & 0x1f]
        set level [expr [expr $mval >> 28] & 0x07]
        
        if {$len == 0} {
            return
        }
        
        incr addr 4
        set endaddr [expr $addr + $text_len]
        incr endaddr [expr $text_len % 4]
        
        set chars 0
        
        # Uncomment below to display a timestamp before the message
        # puts -nonewline "$ts_nsec: "
        
        while {$addr < $endaddr} {
            set mval [linux_mem_read $addr]
            set shift 0
            
            while {$shift <= 24} {
                set char [expr [expr $mval >> $shift] & 0xff]
                incr shift 8
                set text_char [format "%c" $char]
                if {$chars < $text_len} {
                    puts -nonewline "$text_char"
                }
                incr chars 1
            }
            
            incr addr 4
        }
        set addr [expr $startaddr + $len]
        
        puts ""
    }
}
    
proc syslog_write { bufaddr bufsize } {
    set fp [open "syslog_t.txt" w]
    puts $fp [ mrd $buffaddr $bufsize w]
    close $fp
}