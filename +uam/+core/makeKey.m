function key = makeKey(varargin)
    % makeKey 统一生成 containers.Map 的 char key
    %
    %   key = uam.core.makeKey("T1", "fixed_north")
    %   返回 char: 'T1-fixed_north'
    %
    %   解决 string/char 混用导致 Map key 找不到的问题。
    %   所有 Map 操作统一通过此函数生成 key。

    parts = cellfun(@string, varargin);
    key = char(join(parts, "-"));
end
