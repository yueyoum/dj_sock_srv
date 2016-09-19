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
    response/3,
    encode_message/1]).

%% api succeed callback
-export([succeed_callback_party_create/1,
    succeed_callback_socket_connect/1,
    succeed_callback_buy_item/1,
    succeed_callback_party_start/1]).

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

%% PartyRoomRequest
handle(#'ProtoPartyRoomRequest'{},
    #client_state{socket = Socket, transport = Transport, char_id = CharID} = State) ->
    checker = check_msg_undefined_and_char_id_zero(
        <<"PartyRoomRequest">>,
        [],
        CharID
    ),

    case checker of
        ok ->
            InfoList = dj_party_room:get_all_rooms(),
            Fun = fun({ok, OwnerID, OwnerName, Lv, Amount, StartAt}, Acc) ->
                case StartAt > 0 of
                    true -> Acc;
                    false ->
                        Msg = #'ProtoPartyRoomResponse.PartyRoom'{
                            owner_id = integer_to_binary(OwnerID),
                            owner_name = OwnerName,
                            level = Lv,
                            current_amount = Amount
                        },
                        [Msg | Acc]
                end
                  end,

            Response = #'ProtoPartyRoomResponse'{
                ret = 0,
                session = <<>>,
                rooms = lists:foldl(Fun, [], InfoList)
            },

            response(Transport, Socket, Response),
            {ok, State};
        Error ->
            Error
    end;

%% PartyCreateRequest
handle(#'ProtoPartyCreateRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, <<"can not create multi party at same time">>, ?ERROR_CODE_PARTY_CANNOT_CREATE_MULTI_PARTY};

handle(#'ProtoPartyCreateRequest'{}, #client_state{party_create_times = CT}) when CT >= ?MAX_PARTY_CREATE_TIMES ->
    {error, <<"party no create times">>, ?ERROR_CODE_PARTY_NO_CREATE_TIMES};

handle(#'ProtoPartyCreateRequest'{id = PartyLevel},
    #client_state{socket = Socket, transport = Transport, server_id = SID, char_id = CharID} = State) ->

    checker = check_msg_undefined_and_char_id_zero(
        <<"PartyCreateRequest">>,
        [PartyLevel],
        CharID
    ),

    case checker of
        ok ->
            Req = json:to_binary(#{server_id => SID, char_id => CharID, party_level => PartyLevel}),

            api_response_handle(
                party_create,
                Req,
                {?MODULE, succeed_callback_party_create, [PartyLevel, State]},
                Transport,
                Socket
            );
        Error ->
            Error
    end;

%% PartyJoinRequest
handle(#'ProtoPartyJoinRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, <<"can not join due to in other party">>, ?ERROR_CODE_PARTY_CANNOT_JOIN_DUE_TO_IN_OTHER_PARTY};

handle(#'ProtoPartyJoinRequest'{}, #client_state{party_join_times = JT}) when JT >= ?MAX_PARTY_JOIN_TIMES ->
    {error, <<"party no join times">>, ?ERROR_CODE_PARTY_NO_JOIN_TIMES};

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
    end;

%% PartyChatRequest
handle(#'ProtoPartyChatRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, <<"no charid or no room for chat">>, ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyChatRequest'{text = Text},
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->
    case byte_size(Text) of
        0 ->
            {error, <<"chat text is empty">>, ?ERROR_CODE_BAD_MESSAGE};
        N when N > 1000 ->
            {error, <<"chat text too large">>, ?ERROR_CODE_PARTY_CHAT_TO_LARGE};
        _ ->
            dj_party_room:chat(RoomPid, CharID, Text),
            {ok, State}
    end;

%% PartyBuyRequest
handle(#'ProtoPartyBuyRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, <<"no charid or no room for buy">>, ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyBuyRequest'{buy_id = BuyID},
    #client_state{server_id = SID, char_id = CharID, party_room_pid = RoomPid,
        socket = Socket, transport = Transport} = State) ->

    case dj_party_room:buy_check(RoomPid, CharID, BuyID) of
        {ok, Lv, Members} ->
            Req = json:to_binary(#{
                server_id => SID,
                char_id => CharID,
                party_level => Lv,
                buy_id => BuyID,
                member_ids => Members
            }),

            api_response_handle(
                party_buy,
                Req,
                {?MODULE, succeed_callback_buy_item, [BuyID, State]},
                Transport,
                Socket
            );
        Error ->
            Error
    end;


%% PartyStartRequest
handle(#'ProtoPartyStartRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, <<"no charid or no room for start">>, ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyStartRequest'{},
    #client_state{server_id = SID, char_id = CharID, party_room_pid = RoomPid,
        socket = Socket, transport = Transport} = State) ->

    case dj_party_room:start_party(RoomPid, CharID) of
        {ok, Lv, JoinMembers} ->
            Req = json:to_binary(#{
                server_id => SID,
                char_id => CharID,
                party_level => Lv,
                member_ids => JoinMembers
            }),

            api_response_handle(
                party_start,
                Req,
                {?MODULE, succeed_callback_party_start, [State]},
                Transport,
                Socket
            ),

            {ok, State};
        Error ->
            Error
    end;

%% PartyDismissRequest
handle(#'ProtoPartyDismissRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, <<"no charid or no room for dismiss">>, ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyDismissRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->
    case dj_party_room:dismiss_party(RoomPid, CharID) of
        ok ->
            {ok, State};
        Error ->
            Error
    end.


%% =======================

succeed_callback_socket_connect([ApiReturn,
    #client_state{socket = Socket, transport = Transport} = State]) ->

    #{<<"server_id">> := SID, <<"char_id">> := CID,
        <<"flag">> := Flag, <<"name">> := Name,
        <<"party_info">> := PartyInfo} = ApiReturn,

    #{<<"create_times">> := CT, <<"join_times">> := JT} = PartyInfo,

    Info = #{flag => Flag, name => Name},

    % global register self
    true = gproc:reg({n, g, dj_utils:char_id_to_binary_id(CID)}),

    State1 = State#client_state{
        server_id = SID, char_id = CID,
        info = Info,
        party_room_pid = undefined,
        party_create_times = CT,
        party_join_times = JT},

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

    gen_server:cast(self(), send_login_notify),
    {ok, State2}.


succeed_callback_party_create([_, PartyLevel,
    #client_state{server_id = SID, char_id = CharID, info = Info} = State]) ->

    {ok, RoomPid} = dj_party_sup:create_room(SID, CharID, Info, PartyLevel),
    {ok, State#client_state{party_room_pid = RoomPid}}.

succeed_callback_party_start([_, State]) ->
    {ok, State}.

succeed_callback_buy_item([
    #{<<"buy_name">> := BuyName, <<"item_name">> := ItemName},
    BuyId,
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State]) ->

    dj_party_room:buy_done(RoomPid, CharID, BuyId, BuyName, ItemName),
    {ok, State}.


do_party_join(undefined, _State) ->
    {error, <<"join error. can not find room">>, ?ERROR_CODE_PARTY_JOIN_ERROR_NO_ROOM};

do_party_join(RoomPid, #client_state{char_id = CharID, info = Info} = State) ->
    case dj_party_room:join_room(RoomPid, CharID, Info) of
        ok ->
            {ok, State#client_state{party_room_pid = RoomPid}};
        Error ->
            Error
    end.

%% =================================

api_response_handle(Function, Arg, {M, F, A}, Transport, Socket) ->
    case dj_http_client:Function(Arg) of
        {ok, Data, Extra, Others} ->
            Return = M:F([Data | A]),
            % send extra response to client.
            % the extra response generated at http server
            case byte_size(Extra) > 0 of
                true -> response(Transport, Socket, base64:decode(Extra));
                false -> ok
            end,

            api_response_handle_others(Others),
            Return;

        {error, ErrorCode} ->
            CodeBin = integer_to_binary(ErrorCode),
            FuncBin = atom_to_binary(Function, latin1),
            {error, <<FuncBin/binary, <<", error code: ">>/binary, CodeBin/binary>>, ErrorCode}
    end.

api_response_handle_others([]) ->
    ok;

api_response_handle_others([Head | Tail]) ->
    #{<<"char_id">> := CharID, <<"data">> := Data, <<"extra">> := Extra} = Head,
    case gproc:where({n, g, dj_utils:char_id_to_binary_id(CharID)}) of
        undefined ->
            ok;
        Pid ->
            % TODO
            gen_server:cast(Pid, {api_return, Data, Extra})
    end,
    api_response_handle_others(Tail).


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
    response(Transport, Socket, encode_message(Msg)).

encode_message(Msg) ->
    ID = dj_protocol_mapping:get_id(Msg),
    MsgBin = dj_protocol:encode_msg(Msg),
    <<ID:32, MsgBin/binary>>.
