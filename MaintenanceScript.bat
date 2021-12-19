@echo off
	echo:
	echo "Maintenance Tool Automation"
	echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_x.txt 2>&1
	del C:\Users\"%USERNAME%"\Desktop\Maintainment\x.txt 1> null 2>&1
	echo:
	set /p mydate="Enter Date: (DD-MM-YYYY): "
	echo:
	echo:
	set /p firefox="Clean Cache - Data from Firefox (0-NO / 1-SI): "
	set /p chrome="Clean Cache - Data from Chrome (0-NO / 1-SI): "
	set /p edge="Clean Cache - Data from Edge (0-NO / 1-SI): "
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate% > null
echo:
echo:
echo 1. Disk Cleanup
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DISK-CLEANUP >null
	cleanmgr.exe /VERYLOWDISK /dc  1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DISK_CLEANUP.txt 2>&1
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DISK-CLEANUP >null

echo:
echo 2. System File Scan
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\SCAN-FILE-SYSTEM >null
	sfc /scannow 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_FILE_SCAN_SYSTEM.txt 2>&1
	DISM /Online /Cleanup-Image /CheckHealth 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DISM_CHECK_HEALTH.txt 2>&1
	DISM /Online /Cleanup-Image /ScanHealth 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DISM_SCAN_HEALTH.txt 2>&1
	DISM /Online /Cleanup-Image /RestoreHealth 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DISM_RESTORE_HEALTH.txt 2>&1
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt  C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\SCAN-FILE-SYSTEM >null
echo:
echo 3. Windows Updates
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\WINDOWS-UPDATES >null
	wuauclt /detectnow /updatenow 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_MICROSOFT_UPDATES.txt 2>&1
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\WINDOWS-UPDATES >null
echo:
echo 4. Microsoft Store Reset
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\STORE-RESET >null
	wsreset 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_MICROSOFT_STORE_RESET.txt 2>&1
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\STORE-RESET >null

echo:
echo 5. Delete Temporary Files
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-TMP-FILE >null

	mkdir "%tmp%\x" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_MK_TEMP.txt 2>&1
	mkdir "%temp%\x" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_MK_TEMP1.txt 2>&1

	timeout /T 2 >null

	move %tmp%\* "%tmp%\x" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_MV_TEMP.txt 2>&1
	timeout /T 2 >null
	move %temp%\* "%temp%\x" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_MV_TEMP2.txt 2>&1
	timeout /T 2 >null

	del "%temp%\x" /s /q /f 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_TEMP.txt 2>&1
	timeout /T 2 >null
	del "%tmp%\x" /s /q /f 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_TMP.txt 2>&1
	timeout /T 4 >null
	del C:\*.tmp /s /q /f 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_TMP_SOURCE.txt 2>&1
	timeout /T 2 >null

	rmdir "%tmp%\x" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_RM_TEMPX.txt 2>&1
	rmdir "%temp%\x" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_RM_TEMPX1.txt 2>&1

	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-TMP-FILE >null
echo:
echo 6. Delete Browser Cache/Data
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA >null

	if "%firefox%"=="1" (
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\FIREFOX >null
	echo .......... 6.1 Delete Browser Cache/Data Firefox

		set DataDir=%localappdata%\Mozilla\Firefox\Profiles 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_SET_FIREFOX.txt 2>&1
		del /q /s /f "%DataDir%" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_DEL_FIREFOX.txt 2>&1
		rd /s /q "%DataDir%" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_RD_FIREFOX.txt 2>&1

		for /d %%x in (%appdata%\Mozilla\Firefox\Profiles\*) do del /q /s /f %%x\*sqlite   1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_SQLITE_FIREFOX.txt 2>&1
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\FIREFOX >null

	)

	if "%chrome%"=="1" (
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\CHROME >null
	echo .......... 6.2 Delete Browser Cache/Data Chrome
		set DataDir="%localappdata%\Google\Chrome\User Data" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_SET_CHROME.txt 2>&1
		del /q /s /f %DataDir% 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_DEL_CHROME.txt 2>&1
		rd /s /q %DataDir% 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_RD_CHROME.txt 2>&1 	
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\CHROME >null

	)

	if "%edge%"=="1" (
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\EDGE >null
	echo .......... 6.3 Delete Browser Cache/Data Microsoft Edge
		set DataDir="%localappdata%\MicrosoftEdge\User" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_SET_EDGE.txt 2>&1
		del /q /s /f %DataDir% 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_DEL_EDGE.txt 2>&1
		rd /s /q %DataDir% 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_DATA_DIR_RD_EDGE.txt 2>&1 
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\EDGE >null

	)


	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\MV-BROWSER-CACHE-DATA 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_x.txt 2>&1
	del C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_x.txt >nul
echo:
echo 7. Flush DNS
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\FLUSH-DNS >null
	ipconfig /flushdns 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_FLUSH_DNS.txt 2>&1 
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\FLUSH-DNS >null
echo:
echo 8. Battery Report
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\BATTERY-REPORT >null
	powercfg /batteryreport /output "%USERPROFILE%\Desktop\Maintainment\19-12-2021\BATTERY-REPORT\battery-report.html" 1> C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_x.txt
	del C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\log_x.txt >null
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\BATTERY-REPORT >null
echo:
echo 9. Task List
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\TASK-LIST
	tasklist /v > C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\TaskList.txt
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\TASK-LIST >null
echo:
echo 10. Automatic Mantainance
echo -----------------------------
echo:
	mkdir C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\AUTO-MAINTAINANCE >null
	mschedexe.exe start > C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\AUTO-MANTAINANCE.txt
	move C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\*.txt C:\Users\"%USERNAME%"\Desktop\Maintainment\%mydate%\AUTO-MAINTAINANCE >null



cmd /k
