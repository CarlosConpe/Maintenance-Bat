@echo off 
set /p ip="Enter IP: "
set /p subnet="Enter SUBNET: "
set /p gateway="Enter GATEWAY: "
echo 'netsh interface ip set address "Ethernet" static "%ip%" "%subnet%" "%gateway%"'
netsh interface ip set address "Ethernet" static "%ip%" "%subnet%" "%gateway%"
cmd /k