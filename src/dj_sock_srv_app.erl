%%%-------------------------------------------------------------------
%% @doc dj_sock_srv public API
%% @end
%%%-------------------------------------------------------------------

-module(dj_sock_srv_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    %% web
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/", http_index_handler, []},
            {"/feast/", http_feast_handler, []}
        ]}
    ]),

    {ok, _} = cowboy:start_clear(http, 10,
        [{port, 5678}],
        #{env => #{dispatch => Dispatch}}
        ),

    %% socket
    SocketOpts = [
        {port, 5679}
    ],

    {ok, _} = ranch:start_listener(dj_sock_srv, 10, ranch_tcp,
        [{max_connections, infinity} | SocketOpts],
        tcp_handler, []
    ),

    dj_sock_srv_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
