require 'luaOO'

--常用函数转为UpValue

local Set = Class()
function Set:__init__()
  self.reverse = {}
end

function Set:insert(value)
  if not self.reverse[value] then
    table.insert(self, value)
    self.reverse[value] = true
  end
end

function Set:delete(value)
  if not self.reverse[value] then
    return
  end
  
  self.reverse[value] = nil
  for i, v in ipairs(self) do
    if v == value then
      table.remove(self, i)
      break
    end
  end
end

function Set:contains(value)
  return self.reverse[value]
end

local recvset = Set()
local sendset = Set()

TcpSocket = Class()

--句柄管理
local sockets = {}

function TcpSocket:register()
  sockets[self.handle] = self
end

function TcpSocket:unregister()
  sockets[self.handle] = nil
end

function TcpSocket.query(handle)
  return sockets[handle]
end

function TcpSocket.clear()
  --拷贝，防止迭代器失效
  local tcpsockets = {}
  for _, v in pairs(sockets) do
    table.insert(tcpsockets, v)
  end
  
  for _, v in ipairs(tcpsockets) do
    v.close()
  end
end

--为了调试信息
local gid = 1

function TcpSocket:__init__(handle)
  self.handle = handle
  self.handle:settimeout(0.001)
  
  self.recvbuff = ''
  self.sendbuff = ''
  
  self.gid = gid
  gid = gid + 1
  
  self.register()
  
  self.start = get_current_time()
end

function TcpSocket:close()
  if self.closed then return end
  
  self.closed = true
  self.unregister()

  self.handle:close()
  
  recvset.delete(self.handle)
  sendset.delete(self.handle)
  
  print('close: '..self.gid..' '..(get_current_time() - self.start))
  
  if self.thread and coroutine.running() ~= self.thread then
    coroutine.resume(self.thread)
  end
  
end

function TcpSocket:close_on_send_complete()
  self.willclose = true
  if not self.sending then
    self.close()
  end
end

function TcpSocket:write(data)
  if self.closed then return false end

  if type(data) ~= 'string' or #data == 0 then
    return true
  end
  
  if self.sending then
    self.sendbuff = self.sendbuff..data
    return true
  end
  
  local x, e, y = self.handle:send(data, 1)
  if e == 'closed' then
    self.close()
    return false
  end
  
  local sent = x or y
  if type(sent) == 'number' then
    self.sendbuff = string.sub(data, sent + 1)
  end
  if #self.sendbuff > 0 then
    self.sending = true
    sendset.insert(self.handle)
  end
  return true
end

function TcpSocket:read(length)
  local thread, ismain = coroutine.running()
  if ismain or self.closed or self.thread or length <= 0 then return end
  
  self.thread = thread
  recvset.insert(self.handle)
  
  local buff = ''
  while true do
    if #self.recvbuff >= #buff + length then
      buff = buff..string.sub(self.recvbuff, 1, length)
      self.recvbuff = string.sub(self.recvbuff, length + 1)
      break
    end
 
    buff = buff..self.recvbuff
    length = length - #self.recvbuff
    self.recvbuff = ''
    if self.closed then
      break
    end
    
    coroutine.yield()
  end
  
  self.thread = nil
  recvset.delete(self.handle)
  return buff
end

function TcpSocket:readline()
  local thread, ismain = coroutine.running()
  if ismain or self.closed or self.thread then return end
  
  self.thread = thread
  recvset.insert(self.handle)
  
  local buff = ''
  while true do
    local i, j = string.find(self.recvbuff, '\r\n')
    
    if i then
      buff = string.sub(self.recvbuff, 1, i - 1)
      self.recvbuff = string.sub(self.recvbuff, j + 1)
      break
    end
    
    if self.closed then
      buff = self.recvbuff
      self.recvbuff = ''
      break
    end
    print('yield'..self.gid)
    coroutine.yield()
    print('resume'..self.gid)
  end
  
  self.thread = nil
  recvset.delete(self.handle)
  return buff
end

function TcpSocket:handle_recv()
  if self.closed then return end
  
  print('handle_recv'..self.gid)
  
  local notify = false
  while true do
    local x, e, y = self.handle:receive(1024)
    local buff = x or y
    if type(buff) == 'string' and #buff > 0 then
      print('recvbuff:'..self.gid..' '..buff)
      self.recvbuff = self.recvbuff..buff
      notify = true
    end
    
    if e == 'closed' then
      self.close()
      return
    end
    
    if e then
      print(e..self.gid)
    end
    
    if not x then
      break
    end
  end
  
  if notify and self.thread then
    coroutine.resume(self.thread)
  end
end

function TcpSocket:handle_send()
  if self.closed then return end

  if #self.sendbuff == 0 then
    self.sending = false
    sendset.delete(self.handle)
    return
  end
  
  local x, e, y = self.handle:send(self.sendbuff, 1)
  
  local sent = x or y
  if type(sent) == 'number' then
    self.sendbuff = string.sub(self.sendbuff, sent + 1)
  end
  
  if #self.sendbuff == 0 then
    self.sending = false
    sendset.delete(self.handle)
    
    if self.willclose then
      self.close()
    end
  end
end

Application = Class()
function Application:handle_connect(tcpsocket)
  --如果没有覆盖，直接关闭
  tcpsocket.close()
end

function Application:stop()
  self.stopped = true
end

local socket = require('socket')

--不太注重效率
local _callbacks = {}
function add_callback(callback)
  table.insert(callback)
end

local _timeouts = {}
local Timeout = Class()
function Timeout:__init__(callback, delay)
  self.callback = callback
  self.deadline = socket.gettime() + delay
end

function add_timeout(callback, delay)
  table.insert(_timeouts, Timeout(callback, delay))
end

function del_timeout(timeout)
  timeout.callback = nil
end

function get_current_time()
  return socket.gettime()
end

function main_loop(app, port)
  local server, err = socket.bind('0.0.0.0', port, 5)
  if not server then
    print('监听端口失败，原因:'..err)
    return
  end
  
  server:settimeout(0.001)
  recvset.insert(server)
  
  while not app.stopped do
    local readable, writable, err = socket.select(recvset, sendset, 0.001)
    for _, v in ipairs(readable) do
      if v == server then
        local new = v:accept()
        new:setoption('reuseaddr', false)
        print(new:getpeername())
        if new then
          app.handle_connect(TcpSocket(new))
        end
      else
        TcpSocket.query(v).handle_recv()
      end
    end
    
    for _, v in ipairs(writable) do
      TcpSocket.query(v).handle_send()
    end
    
    --处理callback
    if #_callbacks > 0 then
      local callbacks = _callbacks
      _callbacks = {}
      for _, v in ipairs(callbacks) do
        v()
      end
    end
    
    --处理timeouts
    if #_timeouts > 0 then
      local current = socket.gettime()
      local timeouts = _timeouts
      _timeouts = {}
      for _, v in ipairs(timeouts) do
        if v.callback then
          if v.deadline <= current then
            v.callback()
          else
            table.insert(_timeouts, v) --放回去
          end
        end
      end
    end
  end
end
