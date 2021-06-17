@echo off

	mkdir %USERPROFILE%\Desktop\Maintainment > null
	set /p mydate="Enter Date: (DD-MM-YYYY): "
	set /p firefox="Clean Cache - Data from Firefox (0-NO / 1-SI): "
	set /p chrome="Clean Cache - Data from Chrome (0-NO / 1-SI): "
	set /p edge="Clean Cache - Data from Edge (0-NO / 1-SI): "
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate% > null

echo 1. Disk Cleanup
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\DISK-CLEANUP
	cleanmgr.exe /VERYLOWDISK /dc  1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DISK_CLEANUP.txt 2>&1
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\DISK-CLEANUP >null


echo 2. System File Scan
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\SCAN-FILE-SYSTEM
	sfc /scannow 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_FILE_SCAN_SYSTEM.txt 2>&1
	DISM /Online /Cleanup-Image /CheckHealth 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DISM_CHECK_HEALTH.txt 2>&1
	DISM /Online /Cleanup-Image /ScanHealth 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DISM_SCAN_HEALTH.txt 2>&1
	DISM /Online /Cleanup-Image /RestoreHealth 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DISM_RESTORE_HEALTH.txt 2>&1
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt  %USERPROFILE%\Desktop\Maintainment\%mydate%\SCAN-FILE-SYSTEM >null

echo 3. Windows Updates
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\WINDOWS-UPDATES
	wuauclt /detectnow /updatenow 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_MICROSOFT_UPDATES.txt 2>&1
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\WINDOWS-UPDATES >null

echo 4. Microsoft Store Reset
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\STORE-RESET
	wsreset 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_MICROSOFT_STORE_RESET.txt 2>&1
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\STORE-RESET >null

echo 5. Delete Temporary Files
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-TMP-FILE

	mkdir "%tmp%\x" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_MK_TEMP.txt 2>&1
	mkdir "%temp%\x" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_MK_TEMP1.txt 2>&1

	timeout /T 2 >null

	move %tmp%\* "%tmp%\x" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_MV_TEMP.txt 2>&1
	timeout /T 2 >null
	move %temp%\* "%temp%\x" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_MV_TEMP2.txt 2>&1
	timeout /T 2 >null

	del "%temp%\x" /s /q /f 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_TEMP.txt 2>&1
	timeout /T 2 >null
	del "%tmp%\x" /s /q /f 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_TMP.txt 2>&1
	timeout /T 4 >null
	del C:\*.tmp /s /q /f 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_TMP_SOURCE.txt 2>&1
	timeout /T 2 >null

	rmdir "%tmp%\x" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_RM_TEMPX.txt 2>&1
	rmdir "%temp%\x" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_RM_TEMPX1.txt 2>&1

	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-TMP-FILE >null

echo 6. Delete Browser Cache/Data
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA

	if "%firefox%"=="1" (
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\FIREFOX
	echo ################# 6.1 Delete Browser Cache/Data Firefox

		set DataDir=%localappdata%\Mozilla\Firefox\Profiles 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_SET_FIREFOX.txt 2>&1
		del /q /s /f "%DataDir%" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_DEL_FIREFOX.txt 2>&1
		rd /s /q "%DataDir%" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_RD_FIREFOX.txt 2>&1

		for /d %%x in (%appdata%\Mozilla\Firefox\Profiles\*) do del /q /s /f %%x\*sqlite   1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_SQLITE_FIREFOX.txt 2>&1
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\FIREFOX >null
	echo #################-----------------------------
	)

	if "%chrome%"=="1" (
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\CHROME
	echo #################6.2 Delete Browser Cache/Data Chrome
		set DataDir="%localappdata%\Google\Chrome\User Data" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_SET_CHROME.txt 2>&1
		del /q /s /f %DataDir% 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_DEL_CHROME.txt 2>&1
		rd /s /q %DataDir% 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_RD_CHROME.txt 2>&1 	
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\CHROME >null
	echo #################-----------------------------
	)

	if "%edge%"=="1" (
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\EDGE
	echo #################6.3 Delete Browser Cache/Data Microsoft Edge
		set DataDir="%localappdata%\MicrosoftEdge\User" 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_SET_EDGE.txt 2>&1
		del /q /s /f %DataDir% 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_DEL_EDGE.txt 2>&1
		rd /s /q %DataDir% 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_DATA_DIR_RD_EDGE.txt 2>&1 
		mkdir %DataDir%
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA\EDGE >null
	echo #################-----------------------------
	)


	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\DEL-BROWSER-CACHE-DATA

echo 7. Check and Repair Disk
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\CHECK-DISK
	echo y | chkdsk /F 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_CHECKDISK.txt 2>&1 
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\CHECK-DISK >null

echo 8. Flush DNS
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\FLUSH-DNS
	ipconfig /flushdns 1> %USERPROFILE%\Desktop\Maintainment\%mydate%\log_FLUSH_DNS.txt 2>&1 
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\FLUSH-DNS >null

echo 9. Battery Report
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\BATTERY-REPORT
	powercfg /batteryreport /output "%USERPROFILE%\Desktop\Maintainment\%mydate%\BATTERY-REPORT\battery-report.html" > null
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\BATTERY-REPORT >null

echo 10. Task List
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\TASK-LIST
	tasklist /v > %USERPROFILE%\Desktop\Maintainment\%mydate%\TaskList.txt
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\TASK-LIST >null

echo 11. Automatic Mantainance
echo -----------------------------
echo:
	mkdir %USERPROFILE%\Desktop\Maintainment\%mydate%\AUTO-MAINTAINANCE
	mschedexe.exe start > %USERPROFILE%\Desktop\Maintainment\%mydate%\AUTO-MANTAINANCE.txt
	move %USERPROFILE%\Desktop\Maintainment\%mydate%\*.txt %USERPROFILE%\Desktop\Maintainment\%mydate%\AUTO-MAINTAINANCE >null



cmd /k