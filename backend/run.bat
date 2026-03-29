@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Creating venv...
  py -3 -m venv .venv
  call .venv\Scripts\activate.bat
  python -m pip install -U pip
  pip install -r requirements.txt
) else (
  call .venv\Scripts\activate.bat
)
echo Starting API at http://127.0.0.1:8000
python main.py
pause
