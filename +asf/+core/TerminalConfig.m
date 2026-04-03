classdef TerminalConfig
    % TerminalConfig 终端完整配置
    properties
        terminalId  (1,1) string
        x           (1,1) double = 0
        y           (1,1) double = 0
        ports       (:,1) % PortConfig array
        muBar       (1,1) double = 1.0        % 饱和阈值
        psiSat      (1,1) double = 2.0        % 饱和惩罚系数
        coupling    struct = struct()          % 跨端口耦合: coupling.(h1_h2) = m 值
        fpRadius    (1,1) double = 1           % footprint 邻域 hop 数
        fpBasePenalty   struct = struct()       % fpBasePenalty.(edgeId) = π 值
        fpLoadSens      struct = struct()       % fpLoadSens.(edgeId_portId) = ρ 值
        blockedEdges    (:,1) string = string.empty
    end
    methods
        function obj = TerminalConfig(id, x, y, ports, varargin)
            arguments
                id (1,1) string
                x (1,1) double = 0
                y (1,1) double = 0
                ports = asf.core.PortConfig.empty
            end
            arguments (Repeating)
                varargin
            end
            obj.terminalId = id;
            obj.x = x; obj.y = y;
            obj.ports = ports;
            p = inputParser;
            addParameter(p, 'muBar', 1.0);
            addParameter(p, 'psiSat', 2.0);
            addParameter(p, 'coupling', struct());
            addParameter(p, 'fpRadius', 1);
            addParameter(p, 'fpBasePenalty', struct());
            addParameter(p, 'fpLoadSens', struct());
            addParameter(p, 'blockedEdges', string.empty);
            parse(p, varargin{:});
            obj.muBar = p.Results.muBar;
            obj.psiSat = p.Results.psiSat;
            obj.coupling = p.Results.coupling;
            obj.fpRadius = p.Results.fpRadius;
            obj.fpBasePenalty = p.Results.fpBasePenalty;
            obj.fpLoadSens = p.Results.fpLoadSens;
            obj.blockedEdges = p.Results.blockedEdges;
        end
        function n = numPorts(obj)
            n = numel(obj.ports);
        end
        function ids = portIds(obj)
            ids = arrayfun(@(p) p.portId, obj.ports);
        end
        function p = getPort(obj, portId)
            for i = 1:numel(obj.ports)
                if obj.ports(i).portId == portId
                    p = obj.ports(i); return;
                end
            end
            error('Port %s not found in terminal %s', portId, obj.terminalId);
        end
    end
end
