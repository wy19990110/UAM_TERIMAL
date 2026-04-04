@echo off
matlab -batch "cd('C:\Projects\UAM_NET'); run('startup.m'); asf.experiments.runEXP4C('results/exp4c');" > results\exp4c_console.txt 2>&1
