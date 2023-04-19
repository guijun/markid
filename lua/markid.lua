--[[
-- https://github.com/tree-sitter/tree-sitter-go
-- declarations.txt 内包含了编写query需要的一些符号
-- :InspectTree指令，就可以看到对应的query了
-- https://github.com/m-demare/hlargs.nvim 这里应该有一些可以学习的地方
--]]
local ts = require("nvim-treesitter")
local parsers = require("nvim-treesitter.parsers")
local configs = require("nvim-treesitter.configs")

local api_get_node_text = vim.treesitter.get_node_text
local api_nvim_set_hl = vim.api.nvim_set_hl
local api_hl_range = vim.highlight.range
local api_nvim_buf_set_var = vim.api.nvim_buf_set_var
local api_nvim_buf_get_var = vim.api.nvim_buf_get_var
local api_nvim_buf_del_var = vim.api.nvim_buf_del_var

local DEBUG_QUERY = false
local DEBUG_VISIBLE = true

local modulename = "markid"
local namespace = vim.api.nvim_create_namespace(modulename)

-- Global table to store names of created highlight groups
local hl_group_of_identifier = {}
local hl_group_count = 0
local hl_index = 0;
local cache_group_names = {}


local string_to_int = function(str)
  if str == nil then
    return 0
  end
  local int = 0
  for i = 1, #str do
    local c = str:sub(i, i)
    int = int + string.byte(c)
  end
  return int
end

RUNING_NO = false;
RUNING_YES = true;
RUNING_QUIT = 2;

local yield_iter = 100
local highlight_tree_v2 = function(config, query, bufnr, tree, cap_start, cap_end)
  local root_tree = tree:root()
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, cap_start, cap_end)
  local iter_count = 0
  local max_iter = config.limits.max_iter
  local max_col = config.limits.max_col
  local max_textlen = config.limits.max_textlen
  local max_names = config.limits.max_names
  local wrap_off = config.limits.wrap_off
  local api_node_range = nil
  local yield_before = 0
  for id, node in query:iter_captures(root_tree, bufnr, cap_start, cap_end) do
    if true then
      if yield_before > yield_iter then
        coroutine.yield(true)
        yield_before = 0
      else
        yield_before = yield_before + 1
      end
    end
    if false then
      iter_count = iter_count + 1
      if max_iter > 0 and iter_count > max_iter then
        -- 超出最大迭代数量
        break
      end
    end
    if not api_node_range then
      api_node_range = node.range
    end
    local start_row, start_col, end_row, end_col = api_node_range(node)
    if (start_col > max_col) and wrap_off then
      vim.wo.wrap = false
      break
    end
    local name = query.captures[id]
    local fixedIdx = -1
    if name == 'keyword' then
      fixedIdx = 1;
    end

    -- if override or name == modulename then
    if true then
      local text = name
      if fixedIdx < 0 then
        text = api_get_node_text(node, bufnr)
      end
      if max_textlen > 0 and #text > max_textlen then
        text = text:sub(1, max_textlen)
      end

      if DEBUG_QUERY then
        print('query name', 'max_names', max_names, name, text)
      end

      if text ~= nil then
        if max_names > 0 and hl_group_count > max_names then -- reset count
          hl_group_of_identifier = {}
          hl_group_count = 0
        end
        local group_name = hl_group_of_identifier[text]
        if group_name == nil then
          local colors_count = 0
          if not config.colors then
            colors_count = 0
          else
            colors_count = #config.colors
          end
          if colors_count == 0 then
            return
          end

          hl_index = hl_index + 1
          if (hl_index > colors_count) then
            hl_index = 1
          end
          local idx = hl_index
          if #cache_group_names == 0 then
            for i = 1, colors_count, 1 do
              cache_group_names[i] = "mkid" .. i
            end
          end
          group_name = cache_group_names[idx]
          if colors_count >= idx then
            api_nvim_set_hl(0, group_name, { default = true, fg = config.colors[idx] })
          end
          hl_group_of_identifier[text] = group_name
          hl_group_count = hl_group_count + 1
          if DEBUG_QUERY then
            print("hl_group_count", hl_group_count)
          end
        end

        if DEBUG_QUERY then
          print("group_name", group_name, start_row, start_col, end_row, end_col)
        end
        if group_name ~= nil then
          local range_start = { start_row, start_col }
          local range_end = { end_row, end_col }
          api_hl_range(
            bufnr,
            namespace,
            group_name,
            range_start,
            range_end
          )
        end
      end
    end
  end
  return false
end


MarkId_DelayTimer = nil

-- 各buf的协程
MarkId_Routine = {}
-- 各buf的定时执行程序
MarkId_Runner = {}
-- 各buf的状态
MarkId_State = {}

MarkId_Timer = {}

MarkId_Tree = {}

-- 保存已经高亮的区域
MarkIdBufStatus = {
}

MarkIdBufStatus_Affirm = function(bufnr)
  local r = MarkIdBufStatus[bufnr]
  if not r then
    r = {
      HL = {}
    }
    MarkIdBufStatus[bufnr] = r
  end
  return r
end

MarkIdBufStatus_HL_Clear = function(bufnr)
  local status = MarkIdBufStatus_Affirm(bufnr)
  status.HL = {}
end

MarkIdBufStatus_HL_Add = function(bufnr, startRow, endRow)
  local status = MarkIdBufStatus_Affirm(bufnr)
  if #status.HL == 0 then
    table.insert(status.HL, { startRow, endRow })
    return true
  else
    for i = 1, #status.HL, 1 do
      local range = status.HL[i]
      if startRow >= range[1] and endRow <= range[2] then
        print('range[i]', range[1], range[2], startRow, endRow)
        return false
      end

      if startRow <= range[1] and endRow >= range[2] then
        range[1] = startRow
        range[2] = endRow
        return true
      end

      if (startRow >= range[1] and startRow <= range[2]) then
        range[2] = endRow
        return true;
      elseif (endRow >= range[1] and endRow <= range[2]) then
        range[1] = startRow
        return true
      end
    end
    table.insert(status.HL, { startRow, endRow })
    return true
  end
end

MarkId_BytesEnable = {}
MarkId_StartTimer = function(config, bufnr, aCb)
  local old = MarkId_Timer[bufnr]
  if (old) then
    return
    -- vim.fn.timer_stop(old)
  end
  MarkId_Timer[bufnr] = vim.fn.timer_start(config.limits.delay, function()
    vim.fn.timer_stop(MarkId_Timer[bufnr])
    MarkId_Timer[bufnr] = nil
    aCb()
  end)
end

local MarkId_AsyncHL = function(config, query, parser, bufnr, cap_start, cap_end)
  if not MarkId_State[bufnr] == RUNING_NO then
    return
  end
  MarkId_State[bufnr] = RUNING_YES

  local oldtree = MarkId_Tree[bufnr]
  local tree = parser:parse(oldtree)[1]
  MarkId_Tree[bufnr] = tree
  -- tree = tree:copy() -- Is it needed ?
  MarkId_Routine[bufnr] = coroutine.create(function()
    highlight_tree_v2(config, query, bufnr, tree, cap_start, cap_end)
  end)
  MarkId_Runner[bufnr] = function()
    local co_result = false
    if not config.limits.routine then
      while true do
        local Running = MarkId_State[bufnr]
        if Running == RUNING_YES then
          _, co_result = coroutine.resume(MarkId_Routine[bufnr]);
          if (not co_result) then
            break
          end
        else
          break
        end
      end
      MarkId_State[bufnr] = RUNING_NO
      MarkId_Runner[bufnr] = nil
      MarkId_Routine[bufnr] = nil
      MarkId_BytesEnable[bufnr] = true
    else
      _, co_result = coroutine.resume(MarkId_Routine[bufnr]);
      if (co_result) then
        local runner = MarkId_Runner[bufnr]
        if (runner) then
          vim.schedule(runner)
        end
      else
        MarkId_Runner[bufnr] = nil
        MarkId_Routine[bufnr] = nil
        MarkId_State[bufnr] = RUNING_NO
        MarkId_BytesEnable[bufnr] = true
      end
    end
  end
  vim.schedule(MarkId_Runner[bufnr])
end

local MarkId_Clear = function(bufnr)
  MarkId_State[bufnr] = RUNING_NO
  MarkId_Tree[bufnr] = nil
  MarkId_Runner[bufnr] = nil
  MarkId_Routine[bufnr] = nil
  MarkId_BytesEnable[bufnr] = false
  if (MarkId_Timer[bufnr]) then
    vim.fn.timer_stop(MarkId_Timer[bufnr])
    MarkId_Timer[bufnr] = nil
  end
end

local M = {}
local DEBUG = true
M.colors = {
  dark = { "#619e9d", "#9E6162", "#81A35C", "#7E5CA3", "#9E9261", "#616D9E", "#97687B", "#689784", "#999C63", "#66639C" },
  bright = { "#f5c0c0", "#f5d3c0", "#f5eac0", "#dff5c0", "#c0f5c8", "#c0f5f1", "#c0dbf5", "#ccc0f5", "#f2c0f5", "#d8e4bc" },
  medium = { "#c99d9d", "#c9a99d", "#c9b79d", "#c9c39d", "#bdc99d", "#a9c99d", "#9dc9b6", "#9dc2c9", "#9da9c9", "#b29dc9" }
}

M.queries = {
  default = "(identifier) @markid",
  golang = [[
          (identifier) @markid
          (property_identifier) @markid
          (shorthand_property_identifier_pattern) @markid
          (shorthand_property_identifier) @markid
        ]],
  javascript = [[
          (identifier) @markid
          (property_identifier) @markid
          (shorthand_property_identifier_pattern) @markid
          (shorthand_property_identifier) @markid
        ]]
}
M.queries.typescript = M.queries.javascript
-- 正则表达式高亮
M.additional_vim_regex_highlighting = true
M.limits = {
  max_col = 800,         --超过则不再高亮，主要影响minified js
  max_names = -1,        --20000, --not used yet
  max_textlen = 48,
  max_iter = -1,         -- 5000,
  delay = 100,
  override = modulename, -- markid,highlights
  wrap_off = true,
  routine = false
}

local evBytesCount = 0


MarkIdRefreshVisible = nil
function M.init()
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinScrolled" }, {
    callback = function()
      if MarkIdRefreshVisible then
        MarkIdRefreshVisible()
      end
    end
  })

  ts.define_modules {
    markid = {
      module_path = modulename,
      attach = function(bufnr, lang)
        MarkId_Clear(bufnr)

        MarkIdBufStatus_HL_Clear(bufnr)
        local config = configs.get_module(modulename)
        if (config.additional_vim_regex_highlighting) then
          vim.bo[bufnr].syntax = "ON"
        else
          vim.bo[bufnr].syntax = "OFF"
        end
        local override = config.override or M.limits.override

        local _, query = pcall(vim.treesitter.query.get, lang, override)
        if query == nil or query == '' then -- 如果没有，就从配置里拿出来再编译i下
          _, query = pcall(vim.treesitter.query.parse, lang, config.queries[lang] or config.queries["default"])
          if not query then
            return
          end
        end

        local parser = parsers.get_parser(bufnr, lang)
        if parser == nil then
          if DEBUG_QUERY then
            print('get_parser fail.', lang)
          end
          return
        else
          if DEBUG_QUERY then
            print('get_parser ok.', lang)
          end
        end
        local delay = config.limits.delay or 100;

        -- yield 调用间隔
        local yield_iter = 50
        -- 在调用yield前，已迭代的次数



        MarkIdRefreshVisible = function()
          MarkId_StartTimer(config, bufnr, function()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local height = vim.api.nvim_win_get_height(0)
            local cap_start = cursor[1] - height;
            local cap_end = cursor[1] + height;
            if cap_start < 0 then
              cap_start = 0;
            end
            if DEBUG_VISIBLE then
              print('cap_start', cap_start, 'cap_end', cap_end)
            end
            if MarkIdBufStatus_HL_Add(bufnr, cap_start, cap_end) then
              MarkId_AsyncHL(config, query, parser, bufnr, cap_start, cap_end)
            else
              if DEBUG_VISIBLE then
                print("Already highlighted", cap_start, cap_end)
              end
            end
          end)
        end


        if true then
          if false then
            MarkId_AsyncHL(config, query, parser, bufnr, 0, -1)
          else
            MarkIdRefreshVisible()
          end
        end
        parser:register_cbs(
          {
            on_bytes         = function(num_changes, var2, start_row, start_col, bytes_offset, _, _, _, new_end)
              if MarkId_BytesEnable[bufnr] then
                if true then
                  MarkId_StartTimer(config, bufnr, function()
                    parser:parse()
                  end)
                else
                  if true then
                    MarkId_StartTimer(config, bufnr, function()
                      MarkId_AsyncHL(config, query, parser, bufnr, 0, -1)
                    end)
                  else
                    MarkId_AsyncHL(config, query, parser, bufnr, 0, -1)
                  end
                end
              end
            end,
            -- 如果触发了parse操作，则这个函数会被调用
            on_changedtree   = function(changes, tree)
              if DEBUG_QUERY then
                print("on_changedtree", vim.inspect(changes), vim.inspect(tree))
              end
              local cap_start = 0
              local cap_end = -1;
              for i = 1, #changes do
                local change = changes[i]
                if (change[1] < cap_start) then
                  cap_start = change[1]
                end
                if (change[3] > cap_end) then
                  cap_end = change[3];
                end
              end
              if false then
                MarkId_AsyncHL(config, query, parser, bufnr, cap_start, cap_end)
              else
                MarkId_StartTimer(config, bufnr, function()
                  MarkId_AsyncHL(config, query, parser, bufnr, cap_start, cap_end)
                end)
              end
            end,
            on_child_added   = function()
            end,
            on_child_removed = function()
            end
          }
        )
      end,
      detach = function(bufnr)
        vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
        MarkIdBufStatus_HL_Clear(bufnr)
        MarkId_Clear(bufnr)
        MarkId_State[bufnr] = RUNING_QUIT
      end,
      is_supported = function(lang)
        return true
        --  local queries = configs.get_module(modulename).queries
        --  return pcall(vim.treesitter.query.parse, lang, queries[lang] or queries["default"])
      end,
      colors = M.colors.medium,
      queries = M.queries,
      limits = M.limits
    }
  }
end

return M


--[[
    -- 记录定时器，并延迟处理
       mod._refresh = mod.refresh
          mod._refresh_timer = nil
          mod.refresh = function(opts)
            if mod._refresh_timer then
              vim.fn.timer_stop(mod._refresh_timer)
            end
            mod._refresh_timer = vim.fn.timer_start(1000, function()
              mod._refresh_timer = nil
              mod._refresh(opts)
            end)
          end


]]
--[[
            https://github.com/neovim/neovim/blob/faa5d5be4b998427b3378d16ea5ce6ef6f5ddfd0/src/nvim/api/buffer.c
///             - on_bytes: lua callback invoked on change.
///               This callback receives more granular information about the
///               change compared to on_lines.
///               Return `true` to detach.
///               Args:
///               - the string "bytes"
///               - buffer handle
///               - b:changedtick
///               - start row of the changed text (zero-indexed)
///               - start column of the changed text
///               - byte offset of the changed text (from the start of
///                   the buffer)
///               - old end row of the changed text
///               - old end column of the changed text
///               - old end byte length of the changed text
///               - new end row of the changed text
///               - new end column of the changed text
///               - new end byte length of the changed text
            --]]
