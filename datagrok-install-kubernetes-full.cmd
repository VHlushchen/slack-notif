@echo off

:: This script automates the Datagrok local installation and running
:: To see additional actions, run "datagrok-install-kubernetes.cmd help"

setlocal enabledelayedexpansion

set timeout=30

:: Define color codes (limited in cmd)
set GREEN=
set RED=
set YELLOW=
set RESET=

:: Function for displaying messages
:message
echo %1
goto :eof

:: Function for displaying errors
:error
echo !!!%1!!!
goto :eof

:: Function for countdown
:count_down
echo Waiting:
for /L %%i in (%1,-1,1) do (
    echo %%i
    timeout /t 1 >nul
)
echo 0
goto :eof

:Help
echo Script to deploy local kubernetes with Datagrok.
echo.
echo Syntax: datagrok-install-kubernetes.cmd [start/update/delete/purge]
echo options:
echo.
echo Command
echo datagrok-install-kubernetes.cmd start
echo Installing local kubernetes and deploying Datagrok
echo datagrok-install-kubernetes.cmd update
echo Updating the current configuration associated with changes 
echo datagrok-install-kubernetes.cmd delete
echo Removal of Datagrok deployment
echo datagrok-install-kubernetes.cmd purge
echo Full clean up of the Datagrok environment
goto :eof


:deploy_helm
:: Simulate the deployment process in Windows
echo Deploying with Helm...
echo %*
goto :eof

:datagrok_delete
echo Deleting Datagrok deployment in namespace %1...
:: Simulate deletion
goto :eof

:datagrok_purge
echo Purging Datagrok environment in namespace %1...
:: Simulate purge
goto :eof

:start
call :deploy_helm %*
goto :eof

:update
call :deploy_helm %*
goto :eof

:delete
call :datagrok_delete %1
goto :eof

:purge
call :datagrok_purge %1
goto :eof

:: Check for command input and call appropriate functions
if "%1"=="start" call :start %*
if "%1"=="update" call :update %*
if "%1"=="delete" call :delete %*
if "%1"=="purge" call :purge %*
