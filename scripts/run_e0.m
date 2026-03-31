% run_e0.m E0 实验顶层脚本
%
% 用法: run('scripts/run_e0.m')

% 确保路径已设置
projectRoot = fileparts(fileparts(mfilename('fullpath')));
run(fullfile(projectRoot, 'startup.m'));

% 运行实验
savePath = fullfile(projectRoot, 'results', 'e0');
[results, trueResult] = uam.experiments.RunE0.run(savePath);
