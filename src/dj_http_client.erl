%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Sep 2016 上午5:42
%%%-------------------------------------------------------------------
-module(dj_http_client).
-author("wang").


%% API
-export([get/1,
    post/2,
    request/5,
    parse_session/1,
    party_create/1,
    party_start/1,
    party_buy/1]).

-include("dj.hrl").

get(Path) ->
    request(?HTTP_SERVER_HOST, ?HTTP_SERVER_PORT, Path, <<"GET">>, undefined).

post(Path, Body) when is_binary(Body)->
    request(?HTTP_SERVER_HOST, ?HTTP_SERVER_PORT, Path, <<"POST">>, Body).

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

    #{<<"code">> := Code, <<"data">> := Data,
        <<"extra">> := Extra, <<"others">> := Others} = json:from_binary(ResponseBody),
    if
        Code =:= 0 -> {ok, Data, Extra, Others};
        true -> {error, Code}
    end.

parse_session(Data) ->
    post("/api/session/parse/", Data).

party_create(Data) ->
    post("/api/party/create/", Data).

party_start(Data) ->
    post("/api/party/start/", Data).

party_buy(Data) ->
    post("/api/party/buy/", Data).