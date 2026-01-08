REM program_impact.cmd
REM iMPACT batch commands for programming QVision bitfile
REM Update cable type and device number for your hardware
REM Cable selection examples: 
REM   - setcable -p auto (auto-detect)
REM   - setcable -p usb21 (Platform Cable USB II) 
REM   - setcable -p lpt1 (Parallel Cable IV)
setmode -bs
setcable -p auto
identify
assignfile -p 1 -file qvision.bit
REM Update part number for your device and uncomment to program:
REM Examples - Spartan-6: xc6slx16, Spartan-3: xc3s500e
REM program -p 1 -verify
REM quit
REM For now, just identify the chain
quit
