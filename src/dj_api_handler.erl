%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Sep 2016 下午3:21
%%%-------------------------------------------------------------------
-module(dj_api_handler).
-author("wang").

%% API
-export([handle/3,
    dispatch_extra/1]).

-include("dj_player.hrl").
-include("dj_error_code.hrl").
-include("dj_api.hrl").
-include("dj_protocol.hrl").

-spec handle(tuple(), list(), #client_state{}) ->
    {ok, #client_state{}} |
    {error, term()} |
    {error, term(), integer()}.
handle(#'API.Session.ParseDone'{ret = Ret}, [], _State) when Ret =/= 0 ->
    {error, "API Session Parse Errro: " ++ integer_to_list(Ret), Ret};

handle(#'API.Session.ParseDone'{extras = Extras,
    server_id = SID, char_id = CharID, flag = Flag, name = Name,
    partyinfo = PartyInfo},
    [],
    #client_state{socket = Socket, transport = Transport} = State) ->

    #'API.Session.PartyInfo'{max_buy_times = MaxBuyTimes,
        remained_create_times = CT, remained_join_times = JT, talent_id = Talent} = PartyInfo,

    Info = #{flag => Flag, name => Name},

    case dj_global:find_char_pid(CharID) of
        {error, _} -> ok;
        {ok, CharPid} ->
            lager:warning("ODDLY! Char ~p connect, But find old pid: ~p", [CharID, CharPid]),
            gen_server:call(CharPid, shutdown)
    end,

    dj_global:register_char(CharID),

    State1 = State#client_state{
        server_id = SID,
        char_id = CharID,
        info = Info,
        party_room_pid = undefined,
        party_remained_create_times = CT,
        party_remained_join_times = JT,
        party_talent_id = Talent,
        party_max_buy_times = MaxBuyTimes},

    State2 =
        case dj_global:find_char_party_room_pid(CharID) of
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
    dispatch_extra(Extras),
    {ok, State2};


handle(#'API.Union.GetInfoDone'{ret = Ret}, [], _State) when Ret =/= 0 ->
    {error, "API Union GetInfo Errro: " ++ integer_to_list(Ret), Ret};

handle(#'API.Union.GetInfoDone'{extras = Extras, union_id = UnionID}, [],
    #client_state{socket = Socket, transport = Transport} = State) ->

    InfoList = dj_party_room:get_all_rooms(),
    Rooms = make_response_party_room_message(InfoList, UnionID, []),

    Response = #'ProtoPartyRoomResponse'{
        ret = 0,
        session = <<>>,
        rooms = Rooms
    },

    dj_client:response(Transport, Socket, Response),
    dispatch_extra(Extras),
    {ok, State};

handle(#'API.Party.CreateDone'{ret = Ret}, _Args, _State) when Ret =/= 0 ->
    {error, "API Party Create Errro: " ++ integer_to_list(Ret), Ret};


handle(#'API.Party.CreateDone'{extras = Extras, union_id = UnionID}, [PartyLevel],
    #client_state{server_id = SID, char_id = CharID, info = Info} = State) ->

    {ok, RoomPid} = dj_party_sup:create_room(SID, CharID, Info, PartyLevel, UnionID),
    dispatch_extra(Extras),
    {ok, State#client_state{party_room_pid = RoomPid}};

handle(#'API.Party.JoinDone'{ret = Ret}, _Args, _State) when Ret =/= 0 ->
    {error, "API Party Join Errro: " ++ integer_to_list(Ret), Ret};

handle(#'API.Party.JoinDone'{extras = Extras}, [RoomPid],
    #client_state{char_id = CharID, info = Info} = State) ->

    Ret =
    case dj_party_room:join_room(RoomPid, CharID, Info) of
        ok ->
            {ok, State#client_state{party_room_pid = RoomPid}};
        Error ->
            Error
    end,

    dispatch_extra(Extras),
    Ret;

handle(#'API.Party.StartDone'{ret = Ret}, [], _State) when Ret =/= 0 ->
    {error, "API Party Start Errro: " ++ integer_to_list(Ret), Ret};

handle(#'API.Party.StartDone'{extras = Extras}, [], State) ->
    dispatch_extra(Extras),
    {ok, State};

handle(#'API.Party.BuyDone'{ret = Ret}, _Args, _State) when Ret =/= 0 ->
    {error, "API Party Buy Errro: " ++ integer_to_list(Ret), Ret};

handle(#'API.Party.BuyDone'{extras = Extras, buy_name = BuyName,
    item_name = ItemName, item_amount = ItemAmount},
    [BuyId],
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->

    dj_party_room:buy_done(RoomPid, CharID, BuyId, BuyName, ItemName, ItemAmount),
    dispatch_extra(Extras),
    {ok, State}.


dispatch_extra(undefined) ->
    ok;

dispatch_extra([]) ->
    ok;

dispatch_extra([#'API.Common.ExtraReturn'{char_id = CharID, msgs = Msgs} | Rest]) ->
    case dj_global:find_char_pid(CharID) of
        {error, _} -> ok;
        {ok, Pid} -> gen_server:cast(Pid, {send_msg, Msgs})
    end,

    dispatch_extra(Rest).


-spec make_response_party_room_message(list(), binary(), list()) -> list().
make_response_party_room_message([], _, Rooms) ->
    Rooms;

make_response_party_room_message([{ok, _, _, _, _, StartAt, _} | Rest],
    CharUnionID, Rooms) when StartAt > 0 ->
    make_response_party_room_message(Rest, CharUnionID, Rooms);

make_response_party_room_message([{ok, _, _, _, _, _, UnionID} | Rest],
    CharUnionID, Rooms) when UnionID =/= CharUnionID ->
    make_response_party_room_message(Rest, CharUnionID, Rooms);

make_response_party_room_message([{ok, OwnerID, OwnerName, Lv, Amount, _StartAt, _UnionID} | Rest],
    CharUnionID, Rooms) ->
    Msg = #'ProtoPartyRoomResponse.PartyRoom'{
        owner_id = integer_to_binary(OwnerID),
        owner_name = OwnerName,
        level = Lv,
        current_amount = Amount
    },

    make_response_party_room_message(Rest, CharUnionID, [Msg | Rooms]).