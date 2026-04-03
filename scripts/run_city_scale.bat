@echo off
REM 后台启动城市级参数扫描实验（带断点续传）
echo Starting city-scale experiment in background...
start "" /b matlab -batch "run('C:\Projects\UAM_NET\scripts\run_city_scale_checkpoint.m')" > "C:\Projects\UAM_NET\results\city_scale\matlab_stdout.txt" 2>&1
echo MATLAB process launched. Monitor progress:
echo   type C:\Projects\UAM_NET\results\city_scale\city_scale_log.txt
