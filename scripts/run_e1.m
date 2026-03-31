% run_e1.m E1 实验顶层脚本
%
% 用法: run('scripts/run_e1.m')

projectRoot = fileparts(fileparts(mfilename('fullpath')));
run(fullfile(projectRoot, 'startup.m'));

savePath = fullfile(projectRoot, 'results', 'e1');
[results, trueResult] = uam.experiments.RunE1.run(savePath);
