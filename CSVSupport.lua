--[[
    CSVSupport.lua
    CSV规则：
    1 开头是不留空，以行为单位。
    2 可含或不含列名，含列名则居文件第一行。
    3 一行数据不跨行，无空行。
    4 以半角逗号（即，）作分隔符，列为空也要表达其存在。
    5列内容如存在半角引号（即"），替换成半角双引号（""）转义，即用半角引号（即""）将该字段值包含起来。
        说的花里胡哨的，这里直接测试规则，根据Excel测试
        123可以是123也可以是"123"
        "123"是"""123"""
        开头是"时寻找匹配"，用于判断是否中间内容为所需内容，中间的"被转义为""
        123"可以是123"也可以是"123"""，不过Excel偏向后者
        ,表示为","
    6文件读写时引号，逗号操作规则互逆。
    7内码格式不限，可为 ASCII、Unicode 或者其他。
    8不支持数字
    9不支持特殊字符
]]
local _M = {};
local string_gsub = string.gsub;
local string_sub = string.sub;
local string_find = string.find;
local string_len = string.len;
local table_concat = table.concat;
local type = type;
local table_insert = table.insert;
local io_open = io.open;
local io_lines = io.lines;
local table_remove = table.remove;

--[[
    转义字符串到CSV合法内容
]]
local function escape(str)
    if (str == nil) or (type(str) ~= "string") then
        return "";
    end
    if (string_find(str, "\"") ~= nil) or (string_find(str, ",") ~= nil) then --发现任意一个"或者,，则需要转义
        return table_concat({ "\"", string_gsub(str, "\"", "\"\""), "\"" });
    else --正常的
        return str;
    end
end

--[[
    转义CSV合法内容到字符串
    由于解析过程对逐字节扫描，实际上这个函数会拆开分散进解析中，unescape只是为了方便理解写出来
local function unescape(str)
    if (str == nil) or (type(str) ~= "string") then
        return "";
    end
    if (string_find(str, "^\"") ~= nil) then --发现开头的"，则需要转义
        if (string_find(str, "\"$") ~= nil) then --发现结尾的"，则需要截取
            str = string_sub(str, 2, -2);
        end
        return string_gsub(str, "\"\"", "\"");
    else --正常的
        return str;
    end
end
]]

--[[
    按行读取CSV（第二参数true跳过文件识别）
]]
local function csv2lines(csv, is_str)
    local t          = {};
    local line, file = nil, nil;
    if (not is_str) then
        file = io_open(csv, "r");
    end
    if (file == nil) then --字符串
        local function helper(line)
            table_insert(t, line);
            return "";
        end

        helper((csv:gsub("(.-)\r?\n", helper)));
        return t;
    end
    file:close();
    for line in io_lines(csv) do --路径
        table_insert(t, line);
    end
    return t;
end

--[[
    按行解析CSV
]]
local function parse_line(line)
    local t = {};
    local strbuffer = {};
    local linebuffer = {};
    local linelen = string_len(line);
    for i = 1, linelen do
        table_insert(linebuffer, string_sub(line, i, i));
    end
    local curPos = 0; --指针位置
    local openValue = true; --是否开设新区域
    local openQuote = false; --是否开设引号
    while true do
        curPos = curPos + 1; --1开始索引，之前初始化0，进入循环刚好正常工作
        if (curPos > linelen) then
            if (openValue) then--读取完还有值，那就保存
                table_insert(t, table_concat(strbuffer));
                strbuffer = {};
            end
            break;
        end
        local curChar = linebuffer[curPos];
        if (openValue) then--还在开设新区域
            if (curChar == "\"") then
                openValue = false;
                openQuote = true;
            elseif (curChar == ",") then
                table_insert(t, table_concat(strbuffer));
                strbuffer = {};
            else
                table_insert(strbuffer, curChar);
            end
        else
            if (openQuote) then--"开头序列
                if (curChar == "\"") then
                    if (linebuffer[curPos + 1] == "\"") then--转义
                        table_insert(strbuffer, "\"");
                        curPos = curPos + 1;
                    else
                        openValue = true;
                        openQuote = false;
                    end
                else
                    table_insert(strbuffer, curChar);
                end
            else
                if (curChar == "\"") then
                    openValue = false;
                    openQuote = true;
                else
                    table_insert(strbuffer, curChar);
                end
            end
        end
    end
    return t;
end

--[[
    CSV转table（第二参数true跳过文件识别）
]]
local function csv2table(csv, is_str)
    local line_contents = csv2lines(csv, is_str);
    local line_count = #line_contents;
    if (line_count == 0) then --没有
        return {};
    end
    local KeyMap = parse_line(line_contents[1]);
    local is_has_key_mode = (#KeyMap > 0); --第一行有东西就是有key模式
    local ValueMap = {
        KeyMap = KeyMap;
    };
    for i = 2, line_count do
        local line = line_contents[i];
        local line_values = parse_line(line);
        if (is_has_key_mode) then
            local t = {};
            for j = 1, #KeyMap do
                t[KeyMap[j]] = line_values[j];
            end
            table_insert(ValueMap, t);
        else
            table_insert(ValueMap, line_values);
        end
    end
    if(line_contents[line_count]=="")then
        table_remove(ValueMap,#ValueMap)
    end
    return ValueMap;
end

--[[
    table转CSV
]]
local function table2csv(csvT)
    if (type(csvT) ~= "table") then
        return "";
    end
    local t = {};
    local KeyMap = csvT.KeyMap;
    local is_has_key_mode = KeyMap and (#KeyMap > 0); --第一行有东西就是有key模式
    if (is_has_key_mode) then
        local esKeyMap = {};
        for i = 1, #KeyMap do
            table_insert(esKeyMap, escape(KeyMap[i]));
        end
        table_insert(t, table_concat(esKeyMap, ","));
    end
    table_insert(t, "\n");
    for i = 1, #csvT do
        local line = csvT[i];
        local esLine = {};
        if (is_has_key_mode) then
            for j = 1, #KeyMap do
                table_insert(esLine, escape(line[KeyMap[j]]));
            end
        else
            for j = 1, #line do
                table_insert(esLine, escape(line[j]));
            end
        end
        table_insert(t, table_concat(esLine, ","));
        table_insert(t, "\n");
    end
    return table_concat(t);
end

--API导出
_M.csv2table = csv2table;
_M.table2csv = table2csv;
return _M;
