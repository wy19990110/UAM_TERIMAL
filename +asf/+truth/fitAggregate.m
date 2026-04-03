function [aBar, bBar] = fitAggregate(terminal, nSamples)
    % fitAggregate 从 truth model 拟合 M0 聚合服务 L̃(Λ) = ā Λ + b̄ Λ²
    %   假设流量均匀分配到各端口
    arguments
        terminal asf.core.TerminalConfig
        nSamples (1,1) double = 20
    end
    nP = terminal.numPorts();
    if nP == 0, aBar = 0; bBar = 0; return; end

    lambdas = linspace(0, 1.5 * terminal.muBar, nSamples)';
    costs = zeros(nSamples, 1);
    for i = 1:nSamples
        perPort = lambdas(i) / nP;
        loads = containers.Map();
        for p = 1:nP
            loads(char(terminal.ports(p).portId)) = perPort;
        end
        costs(i) = asf.truth.serviceTruth(terminal, loads);
    end
    % 最小二乘: costs = A * [ā; b̄]
    A = [lambdas, lambdas.^2];
    coeffs = A \ costs;
    aBar = coeffs(1);
    bBar = coeffs(2);
end
