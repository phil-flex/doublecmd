
rem Set Double Commander version
set DC_VER=1.0.0

rem Path to subversion
set SVN_EXE="%ProgramFiles%\TortoiseSVN\bin\svn.exe"

rem Path to Inno Setup compiler
set ISCC_EXE="%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"

rem The new package will be created from here
set BUILD_PACK_DIR=%TEMP%\doublecmd-%DATE: =%

rem The new package will be saved here
set PACK_DIR=%CD%\windows\release

rem Create temp dir for building
rem set BUILD_DC_TMP_DIR=%TEMP%\doublecmd-%DC_VER%
set BUILD_DC_TMP_DIR=%BUILD_PACK_DIR%

rm -rf %BUILD_DC_TMP_DIR%
REM %SVN_EXE% export ..\ %BUILD_DC_TMP_DIR%
xcopy /Q /E /Y ..\* %BUILD_DC_TMP_DIR%\

rm -rf %BUILD_DC_TMP_DIR%\install\windows\release\*
rm -rf %BUILD_DC_TMP_DIR%\doublecmd\

rem Save revision number
REM mkdir %BUILD_DC_TMP_DIR%\.svn
REM copy ..\.svn\entries %BUILD_DC_TMP_DIR%\.svn\

rem Prepare package build dir
REM rm -rf %BUILD_PACK_DIR%
REM mkdir %BUILD_PACK_DIR%
REM mkdir %BUILD_PACK_DIR%\release

rem Copy needed files
copy windows\doublecmd.iss %BUILD_PACK_DIR%\
copy windows\portable.diff %BUILD_PACK_DIR%\

rem Get processor architecture
if "%CPU_TARGET%" == "" (
  if "%PROCESSOR_ARCHITECTURE%" == "x86" (
    set CPU_TARGET=i386
    set OS_TARGET=win32
  ) else if "%PROCESSOR_ARCHITECTURE%" == "AMD64" (
    set CPU_TARGET=x86_64
    set OS_TARGET=win64
  )
)


rem Copy libraries
copy windows\lib\%CPU_TARGET%\*.dll    %BUILD_DC_TMP_DIR%\

cd /D %BUILD_DC_TMP_DIR%

rem Build all components of Double Commander
call build.bat beta

rem Prepare install files
cd /D %BUILD_DC_TMP_DIR%
call install\windows\install.bat

cd /D %BUILD_PACK_DIR%
rem Create *.exe package
rem %ISCC_EXE% /F"doublecmd-%DC_VER%.%CPU_TARGET%-%OS_TARGET%" doublecmd.iss
echo %ISCC_EXE% /F"doublecmd-%DC_VER%.%CPU_TARGET%-%OS_TARGET%" doublecmd.iss

pause

rem Move created package
move release\*.exe %PACK_DIR%

rem Create *.zip package
copy NUL doublecmd\doublecmd.inf
zip -9 -Dr %PACK_DIR%\doublecmd-%DC_VER%.%CPU_TARGET%-%OS_TARGET%.zip doublecmd

rem Create help packages
cd /D %BUILD_DC_TMP_DIR%
rem Copy help files
call %BUILD_DC_TMP_DIR%\install\windows\install-help.bat
rem Create help package for each language
cd %BUILD_PACK_DIR%\doublecmd
for /D %%f in (doc\*) do zip -9 -Dr %PACK_DIR%\doublecmd-help-%%~nf-%DC_VER%.noarch.zip %%f

rem Clean temp directories
rem cd \
rem rm -rf %BUILD_DC_TMP_DIR%
rem rm -rf %BUILD_PACK_DIR%
