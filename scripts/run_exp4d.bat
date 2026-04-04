@echo off
matlab -batch "cd('C:\Projects\UAM_NET'); run('startup.m'); asf.experiments.runEXP4D('results/exp4d');" > results\exp4d_console.txt 2>&1
