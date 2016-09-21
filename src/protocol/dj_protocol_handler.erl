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
    {error, "SocketConnectRequest.session is undefined"};

handle(#'ProtoSocketConnectRequest'{session = Session}, #client_state{char_id = 0} = State) ->
    dj_http_client:api_response_handle(
        parse_session,
        Session,
        {?MODULE, succeed_callback_socket_connect, [State]}
    );

handle(#'ProtoSocketConnectRequest'{}, _State) ->
    {error, "ReSend SocketConnectRequest"};

%%

handle(_, #client_state{char_id = CharID}) when CharID =:= 0 ->
    {error, "must send SocketConnectRequest first", ?ERROR_CODE_INVALID_OPERATE};

%% PartyRoomRequest
handle(#'ProtoPartyRoomRequest'{},
    #client_state{socket = Socket, transport = Transport} = State) ->

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

    dj_client:response(Transport, Socket, Response),
    {ok, State};


%% PartyCreateRequest
handle(#'ProtoPartyCreateRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, "party can not create multi party", ?ERROR_CODE_PARTY_CANNOT_CREATE_MULTI_PARTY};

handle(#'ProtoPartyCreateRequest'{}, #client_state{party_remained_create_times = CT}) when CT < 1 ->
    {error, "party no create times", ?ERROR_CODE_PARTY_NO_CREATE_TIMES};

handle(#'ProtoPartyCreateRequest'{id = undefined}, _) ->
    {error, "party create request, bad message", ?ERROR_CODE_BAD_MESSAGE};

handle(#'ProtoPartyCreateRequest'{id = PartyLevel},
    #client_state{server_id = SID, char_id = CharID} = State) ->

    Req = json:to_binary(#{server_id => SID, char_id => CharID, party_level => PartyLevel}),

    dj_http_client:api_response_handle(
        party_create,
        Req,
        {?MODULE, succeed_callback_party_create, [PartyLevel, State]}
    );

%% PartyJoinRequest
handle(#'ProtoPartyJoinRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, "party can not join in other party", ?ERROR_CODE_PARTY_CANNOT_JOIN_DUE_TO_IN_OTHER_PARTY};

handle(#'ProtoPartyJoinRequest'{}, #client_state{party_remained_join_times = JT}) when JT < 1 ->
    {error, "party no join times", ?ERROR_CODE_PARTY_NO_JOIN_TIMES};

handle(#'ProtoPartyJoinRequest'{owner_id = undefined}, _) ->
    {error, "party join request, bad message", ?ERROR_CODE_BAD_MESSAGE};

handle(#'ProtoPartyJoinRequest'{owner_id = OwnerID}, #client_state{char_id = CharID, info = Info} = State) ->
    case dj_global:register_char_party_room(OwnerID) of
        {error, _} ->
            {error, "party join error. can not find room", ?ERROR_CODE_PARTY_JOIN_ERROR_NO_ROOM};
        {ok, Pid} ->
            case dj_party_room:join_room(Pid, CharID, Info) of
                ok ->
                    {ok, State#client_state{party_room_pid = Pid}};
                Error ->
                    Error
            end
    end;

%% PartyQuitRequest
handle(#'ProtoPartyQuitRequest'{}, #client_state{party_room_pid = undefined}) ->
    {error, "party no room for quit", ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyQuitRequest'{}, #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->
    case dj_party_room:quit_room(RoomPid, CharID) of
        ok ->
            {ok, State#client_state{party_room_pid = undefined}};
        Error ->
            Error
    end;


%% PartyKickRequest
handle(#'ProtoPartyKickRequest'{}, #client_state{party_room_pid = undefined}) ->
    {error, "party no room for kick", ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyKickRequest'{id = undefined}, _) ->
    {error, "party kick request, bad message", ?ERROR_CODE_BAD_MESSAGE};

handle(#'ProtoPartyKickRequest'{id = TargetID},
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->

    case dj_party_room:kick_member(RoomPid, CharID, TargetID) of
        ok ->
            {ok, State};
        Error ->
            Error
    end;

%% PartyChatRequest
handle(#'ProtoPartyChatRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, "party no charid or no room for chat", ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyChatRequest'{text = undefined}, _) ->
    {error, "party chat request, bad message", ?ERROR_CODE_BAD_MESSAGE};

handle(#'ProtoPartyChatRequest'{text = Text},
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->
    case byte_size(Text) of
        0 ->
            {error, "party chat text is empty", ?ERROR_CODE_BAD_MESSAGE};
        N when N > 1000 ->
            {error, "party chat text too large", ?ERROR_CODE_PARTY_CHAT_TO_LARGE};
        _ ->
            dj_party_room:chat(RoomPid, CharID, Text),
            {ok, State}
    end;

%% PartyBuyRequest
handle(#'ProtoPartyBuyRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, "party no charid or no room for buy", ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyBuyRequest'{buy_id = undefined}, _) ->
    {error, "party buy request, bad message", ?ERROR_CODE_BAD_MESSAGE};

handle(#'ProtoPartyBuyRequest'{buy_id = BuyID},
    #client_state{server_id = SID, char_id = CharID, party_room_pid = RoomPid} = State) ->

    case dj_party_room:buy_check(RoomPid, CharID, BuyID) of
        {ok, Lv, Members} ->
            Req = json:to_binary(#{
                server_id => SID,
                char_id => CharID,
                party_level => Lv,
                buy_id => BuyID,
                member_ids => Members
            }),

            dj_http_client:api_response_handle(
                party_buy,
                Req,
                {?MODULE, succeed_callback_buy_item, [BuyID, State]}
            );
        Error ->
            Error
    end;


%% PartyStartRequest
handle(#'ProtoPartyStartRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, "party no charid or no room for start", ?ERROR_CODE_INVALID_OPERATE};

handle(#'ProtoPartyStartRequest'{},
    #client_state{server_id = SID, char_id = CharID, party_room_pid = RoomPid} = State) ->

    case dj_party_room:start_party(RoomPid, CharID) of
        {ok, _Lv, JoinMembers} ->
            Req = json:to_binary(#{
                server_id => SID,
                char_id => CharID,
                member_ids => JoinMembers
            }),

            dj_http_client:api_response_handle(
                party_start,
                Req,
                {?MODULE, succeed_callback_party_start, [State]}
            ),

            {ok, State};
        Error ->
            Error
    end;

%% PartyDismissRequest
handle(#'ProtoPartyDismissRequest'{},
    #client_state{char_id = CharID, party_room_pid = RoomPid})
    when CharID =:= 0; RoomPid =:= undefined ->
    {error, "party no charid or no room for dismiss", ?ERROR_CODE_INVALID_OPERATE};

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

    #{<<"remained_create_times">> := CT,
        <<"remained_join_times">> := JT,
        <<"talent_id">> := Talent} = PartyInfo,

    Info = #{flag => Flag, name => Name},

    case dj_global:find_char_pid(CID) of
        {error, _} -> ok;
        {ok, CharPid} ->
            lager:warning("ODDLY! Char " ++ integer_to_list(CID) ++ " connect, But find old pid: " ++ pid_to_list(CharPid)),
            gen_server:call(CharPid, shutdown)
    end,

    dj_global:register_char(CID),

    State1 = State#client_state{
        server_id = SID,
        char_id = CID,
        info = Info,
        party_room_pid = undefined,
        party_remained_create_times = CT,
        party_remained_join_times = JT,
        party_talent_id = Talent},

    State2 =
    case dj_global:find_char_party_room_pid(CID) of
        {error, _} ->
            State1;
        {ok, RoomPid} ->
            State1#client_state{party_room_pid = RoomPid}
    end,

    Response = #'ProtoSocketConnectResponse'{
        ret = 0,
        session = <<>>,
        next_try_at = 0
    },
    dj_client:response(Transport, Socket, Response),

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


%% =================================

encode_message(Msg) ->
    ID = dj_protocol_mapping:get_id(Msg),
    MsgBin = dj_protocol:encode_msg(Msg),
    <<ID:32, MsgBin/binary>>.
