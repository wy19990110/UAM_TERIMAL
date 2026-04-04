@echo off
matlab -batch "cd('C:\Projects\UAM_NET'); run('startup.m'); asf.experiments.runEXP0('results/exp0');" > results\exp0_console.txt 2>&1
