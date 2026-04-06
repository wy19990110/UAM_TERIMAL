@echo off
REM Build script for TRC paper
REM Usage: build.bat [clean]

cd /d "%~dp0"

if "%1"=="clean" (
    echo Cleaning auxiliary files...
    del /q *.aux *.bbl *.blg *.log *.out *.toc *.fls *.fdb_latexmk *.synctex.gz 2>nul
    echo Done.
    goto :eof
)

echo === Pass 1: pdflatex ===
pdflatex -interaction=nonstopmode main.tex
if errorlevel 1 (
    echo [ERROR] pdflatex pass 1 failed. Check main.log for details.
    goto :eof
)

echo === Pass 2: bibtex ===
bibtex main
if errorlevel 1 (
    echo [WARNING] bibtex reported issues. Check main.blg for details.
)

echo === Pass 3: pdflatex ===
pdflatex -interaction=nonstopmode main.tex

echo === Pass 4: pdflatex ===
pdflatex -interaction=nonstopmode main.tex

echo.
echo === Build complete ===
if exist main.pdf (
    echo Output: %~dp0main.pdf
) else (
    echo [ERROR] main.pdf not generated.
)
