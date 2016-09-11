%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Sep 2016 上午7:02
%%%-------------------------------------------------------------------
-module(http_index_handler).
-author("wang").

%% API
-export([init/2]).

init(Req, Opts) ->
    Req1 = cowboy_req:reply(
        200,
        #{<<"content-type">> => <<"application/json">>},
        json:to_binary(#{id => 1, name => <<"abc">>, 3 => d}),
        Req
    ),

    {ok, Req1, Opts}.
