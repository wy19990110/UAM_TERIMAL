@echo off
matlab -batch "cd('C:\Projects\UAM_NET'); run('startup.m'); asf.experiments.runEXP4B('results/exp4b');" > results\exp4b_console.txt 2>&1
