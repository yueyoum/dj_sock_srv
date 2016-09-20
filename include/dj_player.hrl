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
    %% ranch stuffs
    ref,
    socket,
    transport,
    ok,
    closed,
    error,
    %% my stuffs
    server_id           :: non_neg_integer(),
    char_id             :: non_neg_integer(),
    info                :: map(),
    party_room_pid      :: pid() | undefined,
    party_create_times  :: non_neg_integer(),
    party_join_times    :: non_neg_integer(),
    party_talent_id     :: non_neg_integer()
}).


-define(MAX_PARTY_CREATE_TIMES, 100).
-define(MAX_PARTY_JOIN_TIMES, 100).