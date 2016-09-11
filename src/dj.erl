%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Sep 2016 上午7:22
%%%-------------------------------------------------------------------
-module(dj).
-author("wang").

%% API
-export([start/0]).

start() ->
    application:ensure_all_started(dj_sock_srv).