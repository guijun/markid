--[[
-- https://github.com/tree-sitter/tree-sitter-go
-- declarations.txt 内包含了编写query需要的一些符号
-- :InspectTree指令，就可以看到对应的query了
-- https://github.com/m-demare/hlargs.nvim 这里应该有一些可以学习的地方
--]]
local ts = require("nvim-treesitter")
local parsers = require("nvim-treesitter.parsers")
local configs = require("nvim-treesitter.configs")

local modulename = "markid"
local namespace = vim.api.nvim_create_namespace(modulename)

-- Global table to store names of created highlight groups
local hl_group_of_identifier = {}
local hl_group_count = 0
local hl_index = 0;
local markid_timer = 'markid_timer'
local cache_group_names = {}
local loopername = 'markidlooper'




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
  max_col = 800,     --超过则不再高亮，主要影响minified js
  max_names = -1, --20000, --not used yet
  max_textlen = 48,
  max_iter = -1, -- 5000,
  delay = 100,
  override = modulename, -- markid,highlights
  wrap_off = true
}

local api_get_node_text = vim.treesitter.get_node_text
local api_nvim_set_hl = vim.api.nvim_set_hl
local api_hl_range = vim.highlight.range
local api_nvim_buf_set_var = vim.api.nvim_buf_set_var
local api_nvim_buf_get_var = vim.api.nvim_buf_get_var
local api_nvim_buf_del_var = vim.api.nvim_buf_del_var

function M.init()
  ts.define_modules {
    markid = {
      module_path = modulename,
      attach = function(bufnr, lang)
        local config = configs.get_module(modulename)

        if (config.additional_vim_regex_highlighting) then
          vim.bo[bufnr].syntax = "ON"
        else
          vim.bo[bufnr].syntax = "OFF"
        end
        local override = config.override or M.limits.override
        -- local query = vim.treesitter.query.get(lang, modulename)
        local query = vim.treesitter.query.get(lang, override)
        if query == nil or query == '' then -- 如果没有，就从配置里拿出来再编译i下
          query = vim.treesitter.query.parse(lang, config.queries[lang] or config.queries["default"])
        end
        local parser = parsers.get_parser(bufnr, lang)
        local tree = parser:parse()[1]
        local root = tree:root()
        local delay = config.limits.delay or 100;

        -- yield 调用间隔
        local yield_iter = 50
        -- 在调用yield前，已迭代的次数
        local yield_before = 0

        local highlight_tree = function(root_tree, cap_start, cap_end)
          vim.api.nvim_buf_clear_namespace(bufnr, namespace, cap_start, cap_end)
          local iter_count = 0
          local max_iter = config.limits.max_iter
          local max_col = config.limits.max_col
          local max_textlen = config.limits.max_textlen
          local max_names = config.limits.max_names
          local wrap_off = config.limits.wrap_off
          local api_node_range = nil

          for id, node in query:iter_captures(root_tree, bufnr, cap_start, cap_end) do
            if yield_before > yield_iter then
              coroutine.yield(true)
              yield_before = 0
            else
              yield_before = yield_before + 1
            end

            iter_count = iter_count + 1
            if max_iter > 0 and iter_count > max_iter then
              -- 超出最大迭代数量
              break
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
            if override or name == modulename then
              local text = api_get_node_text(node, bufnr)
              if max_textlen > 0 and #text > max_textlen then
                text = text:sub(1, max_textlen)
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
        end

        local co_hl = coroutine.create(function(root)
          highlight_tree(root, 0, -1)
        end)

        local markid_looper = function(root)
          local running = coroutine.resume(co_hl, root)
          if running then
            -- vim.defer_fn(markid_looper, 0)
            local ok, looper = pcall(api_nvim_buf_get_var, bufnr, loopername)
            if ok and looper then
              vim.schedule(looper)
            end
            -- print('Execute Running')
          else
            pcall(api_nvim_buf_del_var, bufnr, loopername)
            -- print('Execute Done')
          end
        end

        if false then
          while coroutine.resume(co_hl, root) do
          end
        else
          api_nvim_buf_set_var(bufnr, loopername, markid_looper)
          markid_looper(root)
        end
        parser:register_cbs(
          {
            on_changedtree = function(changes, tree)
              markid_looper(tree:root())
              -- highlight_tree(tree:root(), 0, -1) -- can be made more efficient, but for plain identifier changes, `changes` is empty
            end
          }
        )
      end,
      detach = function(bufnr)
        vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
        local ok, oldtimer = pcall(vim.api.nvim_buf_get_var, bufnr, markid_timer)
        if ok and oldtimer then
          vim.fn.timer_stop(oldtimer)
          vim.api.nvim_buf_del_var(bufnr, markid_timer)
        end
      end,
      is_supported = function(lang)
        local queries = configs.get_module(modulename).queries
        return pcall(vim.treesitter.query.parse, lang, queries[lang] or queries["default"])
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
