@echo off
cd /d C:\Projects\OncoGlobal
sf apex run --file scripts/apex/InsertSampleData.apex --target-org hackathon-sandbox > scripts/apex/output.txt 2>&1
echo Exit: %ERRORLEVEL% >> scripts/apex/output.txt
