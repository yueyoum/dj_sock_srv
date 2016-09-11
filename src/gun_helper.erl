%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Sep 2016 上午5:42
%%%-------------------------------------------------------------------
-module(gun_helper).
-author("wang").

%% API
-export([get/3,
    post/4]).

get(Host, Port, Path) ->
    request(Host, Port, Path, <<"GET">>, undefined).

post(Host, Port, Path, Body) ->
    request(Host, Port, Path, <<"POST">>, Body).

request(Host, Port, Path, Method, Body) ->
    {ok, ConnPid} = gun:open(Host, Port),

    Ref = monitor(process, ConnPid),

    {ok, _} = gun:await_up(ConnPid, Ref),

    StreamRef = if
        Body =:= undefined -> gun:request(ConnPid, Method, Path, []);
        true -> gun:request(ConnPid, Method, Path, [], Body)
    end,

    {ok, ResponseBody} = gun:await_body(ConnPid, StreamRef, Ref),
    demonitor(Ref, [flush]),
    gun:shutdown(ConnPid),
    {ok, ResponseBody}.
