@echo off
SET THEFILE=W:\workspace\doublecmd-code\doublecmd.exe
echo Linking %THEFILE%
C:\lazarus\fpc\3.0.4\bin\x86_64-win64\ld.exe -b pei-x86-64  --gc-sections    --entry=_mainCRTStartup    -o W:\workspace\doublecmd-code\doublecmd.exe W:\workspace\doublecmd-code\link.res
if errorlevel 1 goto linkend
goto end
:asmend
echo An error occurred while assembling %THEFILE%
goto end
:linkend
echo An error occurred while linking %THEFILE%
:end
