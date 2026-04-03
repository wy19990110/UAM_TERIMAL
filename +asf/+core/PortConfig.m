classdef PortConfig
    % PortConfig 终端的一个进近/离场接口（port）
    properties
        portId      (1,1) string
        directionDeg    (1,1) double = 0      % 扇区中心方向 (度, 0=East, CCW)
        sectorHalfWidth (1,1) double = 45     % 扇区半宽 (度)
        a           (1,1) double = 0.2        % 线性延迟系数
        b           (1,1) double = 0.5        % 二次延迟系数
    end
    methods
        function obj = PortConfig(id, dir, hw, a, b)
            arguments
                id (1,1) string
                dir (1,1) double = 0
                hw (1,1) double = 45
                a (1,1) double = 0.2
                b (1,1) double = 0.5
            end
            obj.portId = id;
            obj.directionDeg = dir;
            obj.sectorHalfWidth = hw;
            obj.a = a;
            obj.b = b;
        end
        function tf = admitsDirection(obj, thetaDeg)
            diff = mod(thetaDeg - obj.directionDeg + 180, 360) - 180;
            tf = abs(diff) <= obj.sectorHalfWidth;
        end
    end
end
