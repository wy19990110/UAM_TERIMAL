% UAM_NET 项目初始化脚本
% 在 MATLAB 中运行此脚本以设置项目路径

projectRoot = fileparts(mfilename('fullpath'));

% 添加项目根目录（包含 +uam 包）
addpath(projectRoot);

% 添加测试和脚本目录
addpath(fullfile(projectRoot, 'tests'));
addpath(fullfile(projectRoot, 'scripts'));

% 确保 results 目录存在
dirs = {'results', 'results/e0', 'results/e1', 'results/city_scale', 'results/figures'};
for i = 1:numel(dirs)
    d = fullfile(projectRoot, dirs{i});
    if ~exist(d, 'dir')
        mkdir(d);
    end
end

fprintf('UAM_NET 项目路径已初始化。\n');
clear projectRoot dirs d i;
