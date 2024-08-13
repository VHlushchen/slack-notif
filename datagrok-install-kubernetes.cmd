@echo off
setlocal enabledelayedexpansion

REM === Function to check required tools ===
call :check_docker
call :check_docker_daemon
call :check_local_bin
call :check_kubectl
call :check_minikube
call :check_helm

REM === Main part of the script starts from here ===

set "helm_version=1.0.2"
set "namespace="
set "host="

REM Flags
set "start=false"
set "update=false"
set "delete=false"
set "purge=false"
set "browser=true"
set "auto_tests=false"
set "verbose=false"

set "database_internal=true"
set "cvm_only=false"
set "core_only=false"
set "jkg=false"
set "h2o=false"
set "jupyter_notebook=false"
set "grok_compute=false"

set "command="

REM Config
set "config_file=false"
set "config_status="
set "config_file_path="

REM Simulate associative arrays using environment variables
set "versions_datagrok=latest"
set "versions_jkg=latest"
set "versions_h2o=latest"
set "versions_grok_compute=latest"
set "versions_grok_connect=latest"
set "versions_jupyter_notebook=latest"

set "db_creds_database_host="
set "db_creds_database_port="
set "db_creds_database_name="
set "db_creds_database_admin_username="
set "db_creds_database_admin_password="
set "db_creds_database_datagrok_username="
set "db_creds_database_datagrok_password="

REM Process arguments
if "%~1"=="" (
    call :datagrok_install
    set "start=true"
)
:arg_loop
if "%~1"=="" goto end_args
    if "%~1"=="install" call :datagrok_install
    if "%~1"=="purge" set "purge=true"
    if "%~1"=="start" set "start=true"
    if "%~1"=="delete" set "delete=true"
    if "%~1"=="update" set "update=true"
    if "%~1"=="help" goto :help
    if "%~1"=="--help" goto :help
    if "%~1"=="-n" shift & set "namespace=%~1"
    if "%~1"=="--config" shift & set "config_file=true" & set "config_file_path=%~1"
    if "%~1"=="-jkg-v" shift & set "versions_jkg=%~1"
    if "%~1"=="-h2o-v" shift & set "versions_h2o=%~1"
    if "%~1"=="-gc-v" shift & set "versions_grok_compute=%~1"
    if "%~1"=="-gn-v" shift & set "versions_grok_connect=%~1"
    if "%~1"=="-jn-v" shift & set "versions_jupyter_notebook=%~1"
    if "%~1"=="-v" shift & set "versions_datagrok=%~1"
    if "%~1"=="--bleeding-edge" set "versions_datagrok=bleeding-edge"
    if "%~1"=="--host" shift & set "host=%~1"
    if "%~1"=="--helm-version" shift & set "helm_version=%~1"
    if "%~1"=="--cvm" set "cvm_only=true"
    if "%~1"=="--auto-tests" set "auto_tests=true"
    if "%~1"=="--datagrok" set "core_only=true"
    if "%~1"=="--verbose" set "verbose=true"
    if "%~1"=="-jkg" set "jkg=true"
    if "%~1"=="-jn" set "jupyter_notebook=true"
    if "%~1"=="-gc" set "grok_compute=true"
    if "%~1"=="-h2o" set "h2o=true"
shift
goto :arg_loop

:end_args

REM Handle auto_tests and update logic
if /i "%auto_tests%"=="true" (
    if /i "%update%"=="false" if /i "%delete%"=="false" (
        set "start=true"
        set "browser=false"
        call :datagrok_install
    )
    if /i "%update%"=="true" (
        set "update=true"
        set "browser=false"
    )
)

REM Handle bleeding-edge logic
if /i "%versions_datagrok%"=="bleeding-edge" (
    if /i "%start%"=="true" (
        echo Version of all services changed to bleeding-edge
        set "versions_datagrok=bleeding-edge"
        set "versions_jkg=bleeding-edge"
        set "versions_h2o=bleeding-edge"
        set "versions_grok_compute=bleeding-edge"
        set "versions_grok_connect=bleeding-edge"
        set "versions_jupyter_notebook=bleeding-edge"
    )
)

REM Config file logic (assuming JSON parsing with jq is handled elsewhere)
if /i "%config_file%"=="true" (
    REM Process the config file here
    echo Config file logic here
)

REM Set namespace if not provided
if "%namespace%"=="" (
    set "namespace=datagrok-%versions_datagrok%"
    set "namespace=%namespace:~1,-1%"
    set "namespace=%namespace:.=-%"
)

REM Start command
if /i "%start%"=="true" (
    set "command=start"
    call :deploy_helm
)

REM Update command
if /i "%update%"=="true" (
    set "command=update"
    call :deploy_helm
)

REM Delete command
if /i "%delete%"=="true" (
    call :datagrok_delete
)

REM Purge command
if /i "%purge%"=="true" (
    call :datagrok_purge
)

goto :eof

REM === Helper functions ===
:check_docker
where docker >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Docker engine is not installed
    echo Please install Docker and Docker Compose plugin by manual: https://docs.docker.com/engine/install/
    exit /b 255
)
goto :eof

:check_docker_daemon
docker info >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Docker daemon is not running
    echo Please launch Docker Desktop application
    exit /b 255
)
goto :eof
:check_local_bin
echo %PATH% | findstr /i /c:"C:\usr\local\bin" >nul
if not errorlevel 1 (
    echo [INFO] C:\usr\local\bin is in the PATH
) else (
    REM Add C:\usr\local\bin to the PATH for the current session
    set "PATH=C:\usr\local\bin;%PATH%"
    echo [INFO] C:\usr\local\bin has been added to the PATH
    REM Permanently add to the user PATH (optional)
    setx PATH "C:\usr\local\bin;%PATH%" >nul
)
goto :eof

:check_kubectl
where kubectl >nul 2>nul
if errorlevel 1 (
    echo [INFO] Installing kubectl...
    powershell -Command "Invoke-WebRequest -Uri https://dl.k8s.io/release/$(Invoke-WebRequest -Uri https://dl.k8s.io/release/stable.txt -UseBasicParsing).trim()/bin/windows/amd64/kubectl.exe -OutFile kubectl.exe"
    move /Y kubectl.exe "%ProgramFiles%\kubectl.exe"
    setx PATH "%ProgramFiles%;%PATH%"
    echo [INFO] kubectl has been installed
    kubectl version --client
) else (
    echo [INFO] kubectl is already installed
)
goto :eof

:check_minikube
where minikube >nul 2>nul
if errorlevel 1 (
    echo [INFO] Installing Minikube...
    powershell -Command "Invoke-WebRequest -Uri https://storage.googleapis.com/minikube/releases/latest/minikube-windows-amd64.exe -OutFile minikube.exe"
    move /Y minikube.exe "%ProgramFiles%\minikube.exe"
    setx PATH "%ProgramFiles%;%PATH%"
    echo [INFO] Configuring Minikube...
    minikube config set driver docker
) else (
    echo [INFO] Minikube is already installed
)

REM Check if Minikube is running
for /f "tokens=2 delims=: " %%a in ('minikube status --output json ^| findstr "Host Kubelet APIServer"') do (
    if not "%%a"=="Running" (
        echo [INFO] Starting Minikube...
        minikube start
        powershell -Command "Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value 'host.minikube.internal'"
        goto :check_context
    )
)
echo [INFO] Minikube is already up and running

:check_context
REM Check and switch to Minikube context in kubectl
for /f "delims=" %%c in ('kubectl config current-context') do set "current_context=%%c"
if not "%current_context%"=="minikube" (
    kubectl config use-context minikube
) else (
    echo [INFO] kubectl already uses the Minikube context
)

REM Check if Nginx Ingress controller is installed
for /f "delims=" %%s in ('minikube addons list --output json ^| findstr "ingress"') do set "ingress_status=%%s"
if "%ingress_status%"=="enabled" (
    echo [INFO] Nginx Ingress controller installed
    timeout /t 30 >nul
) else (
    echo [INFO] Installing Nginx Ingress controller...
    minikube addons enable ingress
    timeout /t 30 >nul
    kubectl get validatingwebhookconfigurations
)
goto :eof

:check_helm
where helm >nul 2>nul
if errorlevel 1 (
    echo [INFO] Installing Helm...
    powershell -Command "Invoke-WebRequest -Uri https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -OutFile get_helm.sh"
    bash get_helm.sh
) else (
    echo [INFO] Helm is already installed
)
goto :eof

:check_any_pod_not_running
set "namespace=%~1"
set "pod_not_running=false"

REM Get the list of pods and their statuses
for /f "tokens=1,2" %%A in ('kubectl get pods -n %namespace% --output=jsonpath^="{range .items[*]}{.metadata.name}{\" \"}{.status.phase}{\"\n\"}{end}"') do (
    if /i "%%B" NEQ "Running" (
        set "pod_not_running=true"
    )
)

if /i "%pod_not_running%"=="true" (
    exit /b 0
) else (
    exit /b 1
)
:check_any_pod_not_ready
set "namespace=%~1"
set "pod_not_ready=false"

REM Get the list of pods and their readiness status
for /f "tokens=1,2" %%A in ('kubectl get pods -n %namespace% --output=jsonpath^="{range .items[*]}{.metadata.name}{\" \"}{range .status.conditions[?(@.type==\"Ready\")]}{.status}{\"\n\"}{end}"') do (
    if /i "%%B" NEQ "True" (
        set "pod_not_ready=true"
    )
)

if /i "%pod_not_ready%"=="true" (
    exit /b 0
) else (
    exit /b 1
)
:datagrok_install
    call :check_docker
    call :check_docker_daemon
    call :check_local_bin
    call :check_kubectl
    call :check_minikube
    call :check_helm
goto :eof

:deploy_helm
echo Deploying Helm...
REM Add deployment logic here
goto :eof

:datagrok_delete
set "namespace=%~1"

REM Check if DataGrok is installed in the specified namespace
helm list -n %namespace% | findstr /i "datagrok" >nul 2>nul
if errorlevel 0 (
    REM Uninstall DataGrok from the specified namespace
    helm uninstall datagrok -n %namespace% >nul 2>nul
    echo [INFO] Release %namespace% uninstalled
    REM Uncomment the following line if you want to delete the namespace as well
    REM kubectl delete namespace %namespace%
) else (
    echo [INFO] %namespace% is not installed
)
goto :eof

:datagrok_purge
set "namespace=%~1"

REM Check if Minikube is running
for /f "tokens=2 delims=: " %%a in ('minikube status --output json ^| findstr "Host"') do set "minikube_status=%%a"
if not "%minikube_status%"=="Running" (
    echo [INFO] Minikube is not running
) else (
    REM Call datagrok_delete function
    call :datagrok_delete %namespace%

    REM Check if the namespace exists and delete it
    kubectl get namespace "%namespace%" >nul 2>nul
    if errorlevel 0 (
        kubectl delete namespace "%namespace%"
        echo [INFO] Namespace %namespace% deleted
    ) else (
        echo [INFO] Namespace %namespace% is not installed
    )

    REM Remove DataGrok entry from the hosts file
    for /f "delims=" %%i in ('minikube ip') do set "minikube_ip=%%i"
    powershell -Command "(Get-Content C:\Windows\System32\drivers\etc\hosts) -replace '^%minikube_ip% datagrok\.datagrok\.internal.*', '' | Set-Content C:\Windows\System32\drivers\etc\hosts"
    echo [INFO] datagrok.datagrok.internal deleted from hosts

    REM Stop and delete Minikube
    echo [INFO] Stopping Minikube...
    minikube stop
    minikube delete

    REM Remove Minikube executable
    del "%ProgramFiles%\minikube.exe" >nul 2>nul
    echo [INFO] Minikube executable deleted
)
goto :eof

:help
echo usage: %~nx0 install^|start^|stop^|update^|reset^|purge
exit /b 1