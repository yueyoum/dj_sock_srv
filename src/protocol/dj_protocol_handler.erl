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

-include("dj_player.hrl").
-include("dj_error_code.hrl").
-include("dj_protocol.hrl").
-include("dj_api.hrl").

%% SocketConnectRequest
handle(#'ProtoSocketConnectRequest'{session = undefined}, _State) ->
    {error, "SocketConnectRequest.session is undefined"};

handle(#'ProtoSocketConnectRequest'{session = Session}, #client_state{char_id = 0} = State) ->
    Res = dj_http_client:parse_session(Session),
    dj_api_handler:handle(Res, [], State);

handle(#'ProtoSocketConnectRequest'{}, _State) ->
    {error, "ReSend SocketConnectRequest"};

%%

handle(_, #client_state{char_id = CharID}) when CharID =:= 0 ->
    {error, "must send SocketConnectRequest first", ?ERROR_CODE_INVALID_OPERATE};

%% PartyRoomRequest
handle(#'ProtoPartyRoomRequest'{}, #client_state{server_id = SID, char_id = CharID} = State) ->
    Res = dj_http_client:union_get_info(SID, CharID),
    dj_api_handler:handle(Res, [], State);

%% PartyCreateRequest
handle(#'ProtoPartyCreateRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, "party can not create multi party", ?ERROR_CODE_PARTY_CANNOT_CREATE_MULTI_PARTY};

handle(#'ProtoPartyCreateRequest'{}, #client_state{party_remained_create_times = CT}) when CT < 1 ->
    {error, "party no create times", ?ERROR_CODE_PARTY_NO_CREATE_TIMES};

handle(#'ProtoPartyCreateRequest'{id = undefined}, _) ->
    {error, "party create request, bad message", ?ERROR_CODE_BAD_MESSAGE};

handle(#'ProtoPartyCreateRequest'{id = PartyLevel},
    #client_state{server_id = SID, char_id = CharID} = State) ->

    Res = dj_http_client:party_create(SID, CharID, PartyLevel),
    dj_api_handler:handle(Res, [PartyLevel], State);

%% PartyJoinRequest
handle(#'ProtoPartyJoinRequest'{}, #client_state{party_room_pid = Pid}) when is_pid(Pid) ->
    {error, "party can not join in other party", ?ERROR_CODE_PARTY_CANNOT_JOIN_DUE_TO_IN_OTHER_PARTY};

handle(#'ProtoPartyJoinRequest'{}, #client_state{party_remained_join_times = JT}) when JT < 1 ->
    {error, "party no join times", ?ERROR_CODE_PARTY_NO_JOIN_TIMES};

handle(#'ProtoPartyJoinRequest'{owner_id = undefined}, _) ->
    {error, "party join request, bad message", ?ERROR_CODE_BAD_MESSAGE};

handle(#'ProtoPartyJoinRequest'{owner_id = OwnerID},
    #client_state{server_id = SID, char_id = CharID} = State) ->
    case dj_global:find_char_party_room_pid(OwnerID) of
        {error, _} ->
            {error, "party join error. can not find room", ?ERROR_CODE_PARTY_JOIN_ERROR_NO_ROOM};
        {ok, Pid} ->
            Res = dj_http_client:party_join(SID, CharID, binary_to_integer(OwnerID)),
            dj_api_handler:handle(Res, [Pid], State)
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

    case dj_party_room:kick_member(RoomPid, CharID, binary_to_integer(TargetID)) of
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
    #client_state{server_id = SID, char_id = CharID,
        party_room_pid = RoomPid, party_max_buy_times = BT} = State) ->

    case dj_party_room:buy_check(RoomPid, CharID, BuyID, BT) of
        {ok, Lv, Members} ->
            Res = dj_http_client:party_buy(SID, CharID, Lv, BuyID, Members),
            dj_api_handler:handle(Res, [BuyID], State);

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
        {ok, Lv, JoinMembers} ->
            Res = dj_http_client:party_start(SID, CharID, Lv, JoinMembers),
            dj_api_handler:handle(Res, [], State);
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


%% =================================

encode_message(Msg) ->
    ID = dj_protocol_mapping:get_id(Msg),
    MsgBin = dj_protocol:encode_msg(Msg),
    <<ID:32, MsgBin/binary>>.
