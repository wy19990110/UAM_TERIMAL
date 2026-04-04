@echo off
matlab -batch "cd('C:\Projects\UAM_NET'); run('startup.m'); asf.experiments.runEXP5('results/exp5');" > results\exp5_console.txt 2>&1
