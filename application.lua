require 'tcpserver'
require 'luaOO'

local table_insert = table.insert
local table_remove = table.remove
local table_getn = rawlen

local file = io.open('index.htm', 'r')
local data = file:read('*a')
file:close()

--字符串函数
local function stringSplit(str, sep)
  local tbl = {}
  local pos = 1
  local fld
  local i,j = str:find(sep)
  while i do
    fld = str:sub(pos, i - 1)
	if #fld ~= 0 then
	  table_insert(tbl, fld)
	end
	pos = j + 1
	i,j = str:find(sep, pos)
  end  
  
  fld = str:sub(pos)
  if #fld ~= 0 then
	table_insert(tbl, fld)
  end
  return tbl
end

local function stringReplace(str, old, new)
  local tar = ''
  local pos = 1
  local i,j = str:find(old)
  while i do
    fld = str:sub(pos, i - 1)
	tar = tar..fld..new
	pos = j + 1
	i,j = str:find(old, pos)
  end
  fld = str:sub(pos)
  tar = tar..fld
  return tar
end

local function stringRFind(str, pattern)
  local pos = 1
  local li,lj
  local ni,nj = str:find(pattern)
  while ni do
    li, lj = ni, nj
    pos = nj + 1
	ni, nj = str:find(pattern, pos)
  end
  return li, lj
end

WebApplication = Class(Application)
function WebApplication:handle_connect(socket)
  print('connected: '..socket.gid)
  local thread = coroutine.create(self.serve)
  coroutine.resume(thread, socket)
end

function WebApplication:serve(socket)
  local start = get_current_time()
  local url = ''
  while not socket.closed do
    local line = socket.readline()
    print(socket.gid..' '..line)
    if line:find('GET') then
      url = stringSplit(line, ' ')[2]
    end
   
    if line and #line == 0 then
        break
    end
  end
  
  if not socket.closed then
    socket.write(data)
    socket.close_on_send_complete()
  end
end

main_loop(WebApplication(), 8080)
