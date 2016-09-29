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


handle(#'API.Party.CreateDone'{ret = Ret}, _Args, _State) when Ret =/= 0 ->
    {error, "API Party Create Errro: " ++ integer_to_list(Ret), Ret};


handle(#'API.Party.CreateDone'{extras = Extras}, [PartyLevel],
    #client_state{server_id = SID, char_id = CharID, info = Info} = State) ->

    {ok, RoomPid} = dj_party_sup:create_room(SID, CharID, Info, PartyLevel),
    dispatch_extra(Extras),
    {ok, State#client_state{party_room_pid = RoomPid}};

handle(#'API.Party.StartDone'{ret = Ret}, [], _State) when Ret =/= 0 ->
    {error, "API Party Start Errro: " ++ integer_to_list(Ret), Ret};

handle(#'API.Party.StartDone'{extras = Extras}, [], State) ->
    dispatch_extra(Extras),
    {ok, State};

handle(#'API.Party.BuyDone'{ret = Ret}, _Args, _State) when Ret =/= 0 ->
    {error, "API Party Buy Errro: " ++ integer_to_list(Ret), Ret};

handle(#'API.Party.BuyDone'{buy_name = BuyName, item_name = ItemName, item_amount = ItemAmount},
    [BuyId],
    #client_state{char_id = CharID, party_room_pid = RoomPid} = State) ->

    dj_party_room:buy_done(RoomPid, CharID, BuyId, BuyName, ItemName, ItemAmount),
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
