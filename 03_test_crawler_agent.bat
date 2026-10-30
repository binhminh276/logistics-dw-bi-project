@echo off
REM ================================================================================
REM File: 03_test_crawler_agent.bat
REM Muc dich: Kiem tra chay Fuel Crawler va tra ma thoat (exit code) cho SQL Server Agent
REM ================================================================================

echo [INFO] Bat dau chay Fuel Crawler...
python "%~dp0mock_api\fuel_crawler.py"

IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Fuel Crawler that bai voi Exit Code: %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo [SUCCESS] Fuel Crawler da hoan thanh thanh cong!
exit /b 0

