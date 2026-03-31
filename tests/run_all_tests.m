% run_all_tests.m 一键运行全部测试
%
% 用法:
%   结果 = run('tests/run_all_tests.m')
%   或在 tests/ 目录下: runtests('.')

import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.DiagnosticsOutputPlugin

% 确保路径已设置
projectRoot = fileparts(fileparts(mfilename('fullpath')));
run(fullfile(projectRoot, 'startup.m'));

% 收集所有测试
suite = TestSuite.fromFolder(fullfile(projectRoot, 'tests'));

% 运行
runner = TestRunner.withTextOutput;
results = runner.run(suite);

% 输出汇总
fprintf('\n========== 测试汇总 ==========\n');
fprintf('通过: %d\n', sum([results.Passed]));
fprintf('失败: %d\n', sum([results.Failed]));
fprintf('错误: %d\n', sum([results.Incomplete]));
fprintf('================================\n');

if any([results.Failed]) || any([results.Incomplete])
    fprintf(2, '存在失败或未完成的测试！\n');
end
