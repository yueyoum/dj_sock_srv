%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Sep 2016 下午6:17
%%%-------------------------------------------------------------------
-author("wang").

-record(client_state, {
    ref,
    socket,
    transport,
    ok,
    closed,
    error,
    server_id           :: non_neg_integer(),
    char_id             :: non_neg_integer(),
    info                :: map(),
    party_room_pid      :: pid() | undefined
}).
