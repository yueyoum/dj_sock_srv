%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Sep 2016 上午5:10
%%%-------------------------------------------------------------------
-module(tcp_handler).
-author("wang").

-behaviour(ranch_protocol).
-define(TIMEOUT, 1000*60).

%% API
-export([start_link/4,
    init/4]).

start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

init(Ref, Socket, Transport, _Opts) ->
    ok = ranch:accept_ack(Ref),
    loop(Socket, Transport).

loop(Socket, Transport) ->
    case Transport:recv(Socket, 8, ?TIMEOUT) of
        {ok, <<_ID:32, Length:32>>} ->
            {ok, <<_Msg/binary>>} = Transport:recv(Socket, Length),
            ok;
        {error, timeout} ->
            ok;
        {error, _Reason} ->
            ok
    end.
