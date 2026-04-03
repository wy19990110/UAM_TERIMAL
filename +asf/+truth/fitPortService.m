function [aTilde, bTilde] = fitPortService(terminal, portId, nSamples)
    % fitPortService 拟合单端口服务曲线 ã λ + b̃ λ²
    %   仅加载目标端口，其余为零
    arguments
        terminal asf.core.TerminalConfig
        portId (1,1) string
        nSamples (1,1) double = 20
    end
    cap = terminal.muBar / max(terminal.numPorts(), 1);
    lambdas = linspace(0, 1.5 * cap, nSamples)';
    costs = zeros(nSamples, 1);
    for i = 1:nSamples
        loads = containers.Map();
        for p = 1:numel(terminal.ports)
            loads(char(terminal.ports(p).portId)) = 0;
        end
        loads(char(portId)) = lambdas(i);
        costs(i) = asf.truth.serviceTruth(terminal, loads);
    end
    A = [lambdas, lambdas.^2];
    coeffs = A \ costs;
    aTilde = coeffs(1);
    bTilde = coeffs(2);
end
