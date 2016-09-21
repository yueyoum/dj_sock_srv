%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Sep 2016 下午1:03
%%%-------------------------------------------------------------------
-module(dj_global).
-author("wang").

%% API
-export([register_char/1,
    register_char_party_room/1,
    register_party_room/0,
    unregister_char/1,
    unregister_char_party_room/1,
    unregister_party_room/0,
    find_char_pid/1,
    find_char_party_room_pid/1,
    find_all_room_pids/0]).

register_char(CharID) ->
    true = gproc:reg({n, g, dj_utils:char_id_to_binary_id(CharID)}),
    lager:info("Char " ++ integer_to_list(CharID) ++ " register with pid: " ++ pid_to_list(self())),
    ok.

register_char_party_room(CharID) ->
    true = gproc:reg({n, g, dj_utils:char_id_to_party_room_key(CharID)}).

register_party_room() ->
    true = gproc:reg({p, g, party_room}).

unregister_char(CharID) ->
    true = gproc:unreg({n, g, dj_utils:char_id_to_binary_id(CharID)}),
    lager:info("Char " ++ integer_to_list(CharID) ++ " unregister with pid: " ++ pid_to_list(self())),
    ok.


unregister_char_party_room(CharID) ->
    true = gproc:unreg({n, g, dj_utils:char_id_to_party_room_key(CharID)}).

unregister_party_room() ->
    true = gproc:unreg({p, g, party_room}).

find_char_pid(CharID) ->
    Pid = gproc:where({n, g, dj_utils:char_id_to_binary_id(CharID)}),
    case Pid of
        undefined ->
            {error, undefined};
        _ ->
            case rpc:call(node(Pid), erlang, is_process_alive, [Pid]) of
                true ->
                    {ok, Pid};
                false ->
                    unregister_char(CharID),
                    {error, dead}
            end
    end.

find_char_party_room_pid(CharID) ->
    RoomPid = gproc:where({n, g, dj_utils:char_id_to_party_room_key(CharID)}),
    case RoomPid of
        undefined ->
            {error, undefined};
        _ ->
            case rpc:call(node(RoomPid), erlang, is_process_alive, [RoomPid]) of
                true ->
                    {ok, RoomPid};
                false ->
                    unregister_char_party_room(CharID),
                    {error, dead}
            end
    end.

find_all_room_pids() ->
    gproc:lookup_pids({p, g, party_room}).