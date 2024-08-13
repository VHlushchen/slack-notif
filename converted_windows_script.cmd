@echo off
setlocal enabledelayedexpansion

REM Define Variables
set namespace=default
set datagrok_version=1.0.0
set jkg_version=1.0.0
set h2o_version=1.0.0

REM Function to deploy helm
:deploy_helm
echo Deploying with Helm in namespace %namespace%...
REM Simulating Helm command
echo helm upgrade datagrok -n %namespace% --set datagrok.container.tag=%datagrok_version% --set datagrok_jkg.container.tag=%jkg_version% --set datagrok_h2o.container.tag=%h2o_version%
goto :eof

REM Main Logic
if "%1"=="start" (
    call :deploy_helm
) else if "%1"=="update" (
    call :deploy_helm
) else (
    echo Invalid command. Use 'start' or 'update'.
)

endlocal
