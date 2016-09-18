%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Sep 2016 下午6:13
%%%-------------------------------------------------------------------
-module(dj_protocol_handler).
-author("wang").

%% API
-export([handle/2,
    error_response/2,
    error_response/3,
    response/3]).

%% api succeed callback
-export([succeed_callback_party_create/1,
    succeed_callback_socket_connect/1]).

-include("dj_player.hrl").
-include("dj_error_code.hrl").
-include("dj_protocol.hrl").

%% SocketConnectRequest
handle(#'ProtoSocketConnectRequest'{session = undefined}, _State) ->
    {error, <<"SocketConnectRequest.session is undefined">>};

handle(#'ProtoSocketConnectRequest'{session = Session},
    #client_state{socket = Socket, transport = Transport, char_id = 0} = State) ->

    api_response_handle(
        parse_session,
        Session,
        {?MODULE, succeed_callback_socket_connect, [State]},
        Transport,
        Socket
    );

handle(#'ProtoSocketConnectRequest'{}, _State) ->
    {error, <<"ReSend SocketConnectRequest">>};

%% PartyCreateRequest
handle(#'ProtoPartyCreateRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, <<"can not create multi party at same time">>, ?ERROR_CODE_PARTY_CANNOT_CREATE_MULTI_PARTY};

handle(#'ProtoPartyCreateRequest'{id = ID},
    #client_state{socket = Socket, transport = Transport, char_id = CharID} = State) ->

    checker = check_msg_undefined_and_char_id_zero(
        <<"PartyCreateRequest">>,
        [ID],
        CharID
    ),

    case checker of
        ok ->
            api_response_handle(
                party_create,
                integer_to_binary(ID),
                {?MODULE, succeed_callback_party_create, [ID, State]},
                Transport,
                Socket
            );
        Error ->
            Error
    end;

%% PartyJoinRequest
handle(#'ProtoPartyJoinRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, <<"can not join due to in other party">>, ?ERROR_CODE_PARTY_CANNOT_JOIN_DUE_TO_IN_OTHER_PARTY};

handle(#'ProtoPartyJoinRequest'{owner_id = OwnerID}, #client_state{char_id = CharID} = State) ->
    checker = check_msg_undefined_and_char_id_zero(
        <<"PartyJoinRequest">>,
        [OwnerID],
        CharID
    ),

    case checker of
        ok ->
            RoomPid = gproc:where({n, g, dj_utils:char_id_to_party_room_key(OwnerID)}),
            do_party_join(RoomPid, State);
        Error ->
            Error
    end;

%% PartyQuitRequest
handle(#'ProtoPartyQuitRequest'{}, #client_state{party_room_pid = undefined}) ->
    {error, <<"no room for quit">>, ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyQuitRequest'{}, #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->
    checker = check_msg_undefined_and_char_id_zero(
        <<"PartyQuitRequest">>,
        [],
        CharID
    ),

    case checker of
        ok ->
            case dj_party_room:quit_room(RoomPid, CharID) of
                ok ->
                    % TODO notify ???
                    {ok, State#client_state{party_room_pid = undefined}};
                Error ->
                    Error
            end;
        Error ->
            Error
    end;

%% PartyKickRequest
handle(#'ProtoPartyKickRequest'{}, #client_state{party_room_pid = undefined}) ->
    {error, <<"no room for kick">>, ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyKickRequest'{id = TargetID},
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->

    checker = check_msg_undefined_and_char_id_zero(
        <<"PartyKickRequest">>,
        [TargetID],
        CharID
    ),

    case checker of
        ok ->
            case dj_party_room:kick_member(RoomPid, CharID, TargetID) of
                ok ->
                    {ok, State};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.


%% =======================

succeed_callback_socket_connect([
    #{<<"server_id">> := SID, <<"char_id">> := CID},
    #client_state{socket = Socket, transport = Transport} = State]) ->

    Doc = dj_mongo_client:find_one(<<"character">>, [{<<"_id">>, CID}]),
    #{flag := Flag, name := Name, level := Lv} = Doc,
    Info = #{flag => Flag, name => Name, level => Lv},

    % global register self
    true = gproc:reg({n, g, dj_utils:char_id_to_binary_id(CID)}),

    State1 = State#client_state{server_id = SID, char_id = CID,
        info = Info,
        party_room_pid = undefined},

    Key = {n, g, dj_utils:char_id_to_party_room_key(CID)},
    RoomPid = gproc:where(Key),
    State2 = if
                 RoomPid =:= undefined ->
                     % new, not create or join party
                     State1;
                 true ->
                     State1#client_state{party_room_pid = RoomPid}
             end,

    Response = #'ProtoSocketConnectResponse'{
        ret = 0,
        session = <<>>,
        next_try_at = 0
    },
    response(Transport, Socket, Response),
    {ok, State2}.


succeed_callback_party_create([_, ID,
    #client_state{server_id = SID, char_id = CharID, info = Info} = State]) ->

    {ok, RoomPid} = dj_party_sup:create_room(SID, CharID, Info, ID),
    {ok, State#client_state{party_room_pid = RoomPid}}.

do_party_join(undefined, _State) ->
    {error, <<"join error. can not find room">>, ?ERROR_CODE_PARTY_JOIN_ERROR_NO_ROOM};

do_party_join(RoomPid, #client_state{char_id = CharID} = State) ->

    case dj_party_room:join_room(RoomPid, CharID) of
        ok ->
            {ok, State#client_state{party_room_pid = RoomPid}};
        Error ->
            Error
    end.

%% =================================

api_response_handle(Function, Arg, {M, F, A}, Transport, Socket) ->
    case dj_http_client:Function(Arg) of
        {ok, Data} ->
            Return = M:F([Data | A]),
            % send extra response to client.
            % the extra response generated at http server
            case maps:find(<<"extra">>, Data) of
                error -> ok;
                {ok, Extra} ->
                    case byte_size(Extra) > 0 of
                        true -> response(Transport, Socket, base64:decode(Extra));
                        false -> ok
                    end
            end,
            Return;

        {error, ErrorCode} ->
            CodeStr = integer_to_list(ErrorCode),
            FuncStr = atom_to_list(Function),
            {error, <<FuncStr, ", error code: ", CodeStr>>, ErrorCode}
    end.


check_msg_undefined_and_char_id_zero(MsgName, _MsgFields, 0) ->
    {error,  <<MsgName/binary, <<" char_id is 0">>/binary >>};

check_msg_undefined_and_char_id_zero(MsgName, MsgFields, _CharID) ->
    Checker = fun(F) -> F =:= undefined end,
    case lists:any(Checker, MsgFields) of
        true ->
            {error, <<MsgName/binary, <<" has undefined fields">>/binary >>, ?ERROR_CODE_BAD_MESSAGE};
        false ->
            ok
    end.

error_response(Transport, Socket) ->
    error_response(Transport, Socket, ?ERROR_CODE_INVALID_OPERATE).

error_response(Transport, Socket, ErrorCode) ->
    Response = #'ProtoSocketConnectResponse'{
        ret = ErrorCode,
        session = <<>>,
        next_try_at = 0
    },

    ResponseBin = dj_protocol:encode_msg(Response),
    ResponseID = dj_protocol_mapping:get_id(Response),

    Transport:send(Socket, [<<ResponseID:32>>, ResponseBin]),
    ok.

response(Transport, Socket, MsgBin) when is_binary(MsgBin)->
    ok = Transport:send(Socket, MsgBin);

response(Transport, Socket, Msg) ->
    ID = dj_protocol_mapping:get_id(Msg),
    MsgBin = dj_protocol:encode_msg(Msg),
    response(Transport, Socket, <<ID:32, MsgBin/binary>>).

