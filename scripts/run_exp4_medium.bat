@echo off
echo Starting EXP-4 medium sweep in background...
start "" /b matlab -batch "cd('C:\Projects\UAM_NET'); run('startup.m'); asf.experiments.runEXP4('medium', 'results/exp4');"
echo MATLAB process launched. Monitor:
echo   type C:\Projects\UAM_NET\results\exp4\exp4_medium_log.txt
