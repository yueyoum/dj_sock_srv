%%%-------------------------------------------------------------------
%% @doc dj_sock_srv public API
%% @end
%%%-------------------------------------------------------------------

-module(dj_sock_srv_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

-include("dj.hrl").

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    %% web
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/", http_index, []}
        ]}
    ]),

    {ok, HttpPort} = application:get_env(dj_sock_srv, http_port),
    {ok, TcpPort} = application:get_env(dj_sock_srv, tcp_port),

    {ok, _} = cowboy:start_clear(http, 50,
        [{port, HttpPort}],
        #{env => #{dispatch => Dispatch}}
        ),

    %% socket
    SocketOpts = [
        {port, TcpPort}
    ],

    {ok, _} = ranch:start_listener(dj_sock_srv, 50, ranch_tcp,
        [{max_connections, infinity} | SocketOpts],
        dj_client, []
    ),

    dj_sock_srv_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
