@echo off
setlocal enabledelayedexpansion

REM Example of setting variables
set name=Datagrok
set version=1.0.0

REM Example of a function
:deploy
echo Deploying %name% version %version%
goto :eof

REM Example of an if condition
if "%1"=="start" (
    call :deploy
)
endlocal
