classdef DelayModel
    % DelayModel 终端区延误模型
    %
    %   基于排队论计算稳态延误，拟合为参数化函数：
    %     D(λ) = alpha * (λ / (μ - λ))^beta
    %
    %   内部计算：
    %     - 起降坪排队延误（M/D/c 近似）
    %     - 环形等待延误（与环形占用成正比）
    %     - 合流冲突延误（与冲突流比例成正比）

    methods (Static)
        function [alpha, beta] = fitDelayParams(styleConfig, mu)
            % fitDelayParams 通过多点采样拟合延误函数参数
            %
            %   在多个到达率下计算精确延误，拟合 alpha 和 beta

            if mu <= 0
                alpha = Inf; beta = 1; return;
            end

            % 采样点：10% 到 90% 负载率
            rhos = [0.1, 0.3, 0.5, 0.7, 0.85];
            lambdas = rhos * mu;
            delays = zeros(size(lambdas));

            for i = 1:numel(lambdas)
                delays(i) = uam.terminal.DelayModel.computeRawDelay( ...
                    styleConfig, lambdas(i), mu);
            end

            % 拟合 D(λ) = alpha * (λ/(μ-λ))^beta
            % 取对数线性回归：log(D) = log(alpha) + beta * log(λ/(μ-λ))
            ratios = lambdas ./ (mu - lambdas);
            validIdx = delays > 0 & ratios > 0;

            if sum(validIdx) < 2
                alpha = 0.1; beta = 1.0; return;
            end

            logR = log(ratios(validIdx));
            logD = log(delays(validIdx));

            % 最小二乘拟合
            X = [ones(sum(validIdx), 1), logR(:)];
            coeffs = X \ logD(:);

            alpha = exp(coeffs(1));
            beta = max(0.5, min(3.0, coeffs(2)));  % 限制在合理范围
        end

        function d = computeRawDelay(styleConfig, arrivalRate, mu)
            % computeRawDelay 计算给定到达率下的总延误（秒）
            %
            %   总延误 = 起降坪排队延误 + 环形等待延误 + 合流延误

            if arrivalRate <= 0
                d = 0; return;
            end
            if arrivalRate >= mu
                d = Inf; return;
            end

            rho = arrivalRate / mu;
            c = styleConfig.padCount;           % 服务台数
            serviceTime = styleConfig.serviceTime;  % 秒

            % 1. 起降坪排队延误（M/D/c 近似）
            %    M/D/c 的等待时间约为 M/M/c 的一半（确定性服务时间）
            dPad = uam.terminal.DelayModel.mdcDelay(arrivalRate, mu, c, serviceTime);

            % 2. 环形等待延误
            %    与环形半径成正比，与负载率成正比
            ringCircuit = 2 * pi * styleConfig.ringRadiusNm * 60;  % 海里 → 秒（假设60kt）
            dRing = ringCircuit * rho / (1 - rho + 0.1);  % 加 0.1 防止除零

            % 3. 合流延误（含 waitingSlots 缓冲饱和效应）
            %    缓冲占用率越高，延误越陡（非线性放大）
            waitingOccupancy = min(1, arrivalRate * serviceTime / 3600 / styleConfig.waitingSlots);
            saturationFactor = 1 / (1 - waitingOccupancy + 0.05);  % 饱和放大
            dMerge = 10 * waitingOccupancy * saturationFactor;  % 秒

            d = dPad + dRing + dMerge;
        end

        function [alphas, betas, capMaxes] = fitDelayParamsPerInterface(styleConfig, mu)
            % fitDelayParamsPerInterface 对每个接口拟合延误参数
            %
            %   每接口分配等比容量，独立拟合 D_{t,h}
            %   如果有 interfaceDirections，"detour" 接口延误放大 3 倍
            nH = numel(styleConfig.feasibleCorridors);
            if nH == 0
                alphas = []; betas = []; capMaxes = []; return;
            end

            muPerH = mu / nH;
            capMaxes = repmat(muPerH, nH, 1);
            alphas = zeros(nH, 1);
            betas = zeros(nH, 1);

            for h = 1:nH
                virtualConfig = styleConfig;
                virtualConfig.padCount = max(1, styleConfig.padCount / nH);

                % 根据接口方向调整延误特性
                delayScale = 1.0;
                if ~isempty(styleConfig.interfaceDirections) && h <= numel(styleConfig.interfaceDirections)
                    dir = styleConfig.interfaceDirections(h);
                    if dir == "detour"
                        delayScale = 3.0;  % 绕行接口延误放大
                        virtualConfig.ringRadiusNm = styleConfig.ringRadiusNm * 2;
                    end
                end

                if muPerH <= 0
                    alphas(h) = Inf; betas(h) = 1; continue;
                end

                rhos = [0.1, 0.3, 0.5, 0.7, 0.85];
                lambdas = rhos * muPerH;
                delays = zeros(size(lambdas));
                for i = 1:numel(lambdas)
                    delays(i) = uam.terminal.DelayModel.computeRawDelay( ...
                        virtualConfig, lambdas(i), muPerH) * delayScale;
                end

                ratios = lambdas ./ (muPerH - lambdas);
                validIdx = delays > 0 & ratios > 0;
                if sum(validIdx) < 2
                    alphas(h) = 0.1; betas(h) = 1.0; continue;
                end

                X = [ones(sum(validIdx), 1), log(ratios(validIdx))'];
                coeffs = X \ log(delays(validIdx))';
                alphas(h) = exp(coeffs(1));
                betas(h) = max(0.5, min(3.0, coeffs(2)));
            end
        end

        function [aggAlpha, aggBeta] = fitAggDelayParams(styleConfig, mu)
            % fitAggDelayParams 标定 A0 用的聚合延误 D_agg
            %
            %   在"均匀分配到各接口"条件下，用中观模型计算总延误量，
            %   拟合 D_agg(λ_total) = aggAlpha * (λ_total/(μ-λ_total))^aggBeta

            if mu <= 0
                aggAlpha = Inf; aggBeta = 1; return;
            end

            rhos = [0.1, 0.3, 0.5, 0.7, 0.85];
            lambdas = rhos * mu;
            delays = zeros(size(lambdas));

            for i = 1:numel(lambdas)
                % 均匀分配到各接口后计算总延误
                delays(i) = uam.terminal.DelayModel.computeRawDelay( ...
                    styleConfig, lambdas(i), mu);
            end

            ratios = lambdas ./ (mu - lambdas);
            validIdx = delays > 0 & ratios > 0;
            if sum(validIdx) < 2
                aggAlpha = 0.1; aggBeta = 1.0; return;
            end

            X = [ones(sum(validIdx), 1), log(ratios(validIdx))'];
            coeffs = X \ log(delays(validIdx))';
            aggAlpha = exp(coeffs(1));
            aggBeta = max(0.5, min(3.0, coeffs(2)));
        end

        function d = mdcDelay(lambda, mu, c, serviceTime)
            % mdcDelay M/D/c 近似排队延误
            %
            %   使用 Cosmetatos 近似：M/D/c ≈ M/M/c * (1 + cv^2)/2
            %   对 M/D/c（确定性服务），cv=0，所以 W_q(M/D/c) ≈ W_q(M/M/c)/2

            rho = lambda / mu;
            if rho >= 1 || c < 1
                d = Inf; return;
            end

            rhoPerServer = rho / c;

            % Erlang-C: P(等待) 概率
            % 使用迭代公式避免大阶乘
            sumTerms = 1;
            term = 1;
            for n = 1:c-1
                term = term * (c * rhoPerServer) / n;
                sumTerms = sumTerms + term;
            end
            lastTerm = term * (c * rhoPerServer) / c;
            pC = lastTerm / (lastTerm + (1 - rhoPerServer) * sumTerms);

            % M/M/c 平均等待时间
            wqMMC = pC * serviceTime / (c * (1 - rhoPerServer));

            % M/D/c 近似：确定性服务时间约为 M/M/c 的一半
            d = wqMMC / 2;
        end
    end
end
