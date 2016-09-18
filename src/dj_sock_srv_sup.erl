%%%-------------------------------------------------------------------
%% @doc dj_sock_srv top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(dj_sock_srv_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
%%    PoolArgs = [{name, {local, pool1}}, {worker_module, dj_mongo_client}, {size, 3}, {max_overflow, 5}],
%%    PoolSpec = poolboy:child_spec(pool1, PoolArgs, []),

    PartySupSpec = {dj_party_sup, {dj_party_sup, start_link, []},
        permanent, infinity, supervisor, [dj_party_sup]},

    {ok, { {one_for_one, 0, 1}, [PartySupSpec]} }.

%%====================================================================
%% Internal functions
%%====================================================================
