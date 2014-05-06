lua_tcpserver
=============
based on @lua5.2.3, @luasocket and @luaOO

similar to tornado, but simpler

fork a coroutine for each connection to serve, network operations are none-block and async.

application.lua is just a demo.

quality is not guaranteed, enjoy it.

application.lua requires @luajson


some problem, connection establishing is quite slow, maybe because of select model
