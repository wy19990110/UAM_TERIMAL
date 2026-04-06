@echo off
REM Build script for TRC paper (Chinese version, requires XeLaTeX + ctex)
REM Usage: build_cn.bat [clean]

cd /d "%~dp0"

if "%1"=="clean" (
    echo Cleaning auxiliary files...
    del /q main_cn.aux main_cn.bbl main_cn.blg main_cn.log main_cn.out main_cn.toc main_cn.fls main_cn.fdb_latexmk main_cn.synctex.gz 2>nul
    echo Done.
    goto :eof
)

echo === Pass 1: xelatex ===
xelatex -interaction=nonstopmode main_cn.tex
if errorlevel 1 (
    echo [ERROR] xelatex pass 1 failed. Check main_cn.log for details.
    goto :eof
)

echo === Pass 2: bibtex ===
bibtex main_cn
if errorlevel 1 (
    echo [WARNING] bibtex reported issues. Check main_cn.blg for details.
)

echo === Pass 3: xelatex ===
xelatex -interaction=nonstopmode main_cn.tex

echo === Pass 4: xelatex ===
xelatex -interaction=nonstopmode main_cn.tex

echo.
echo === Build complete ===
if exist main_cn.pdf (
    echo Output: %~dp0main_cn.pdf
) else (
    echo [ERROR] main_cn.pdf not generated.
)
