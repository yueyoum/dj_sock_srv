%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Sep 2016 上午9:55
%%%-------------------------------------------------------------------
-module(dj_party_room).
-author("wang").

-behaviour(gen_server).

%% API
-export([start_link/4,
    get_all_rooms/0,
    get_room_info/1,
    get_simple_room_info/1,
    get_room_message/1,
    start_party/2,
    dismiss_party/2,
    join_room/3,
    quit_room/2,
    kick_member/3,
    chat/3,
    buy_check/3,
    buy_done/5,
    kill_room_by_char_id/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-export([succeed_callback_party_end/1]).

-include("dj_protocol.hrl").
-include("dj_error_code.hrl").

-record(room_message, {
    tp          :: pos_integer(),
    args        :: [string()]
}).

-record(room_member, {
    char_id     :: pos_integer(),
    joined_at   :: pos_integer(),
    info        :: map(),
    buy_info    :: map()
}).

-record(room, {
    sid         :: pos_integer(),   % server id
    owner       :: pos_integer(),   % char id, not pid
    level       :: pos_integer(),   % room level, config id
    seats       :: map(),          % #{seat_id => #room_member{}}
    messages    :: [#room_message{}],
    create_at   :: pos_integer(),   % utc timestamp
    start_at    :: integer()       % utc timestamp. 0 means not start
}).

-define(ROOM_SURVIVAL_TIME, 1000 * 300 ).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(pos_integer(), pos_integer(), map(), pos_integer()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(ServerID, FromID, CharInfo, RoomLevel) ->
    gen_server:start_link(?MODULE, [ServerID, FromID, CharInfo, RoomLevel], []).

get_all_rooms() ->
    PidList = dj_global:find_all_room_pids(),
    rpc:pmap({?MODULE, get_simple_room_info}, [], PidList).

get_room_info(undefined) ->
    undefined;

get_room_info(RoomPid) ->
    gen_server:call(RoomPid, party_info).

get_simple_room_info(RoomPid) ->
    gen_server:call(RoomPid, simple_party_info).

get_room_message(undefined) ->
    make_proto_party_message([]);

get_room_message(RoomPid) ->
    gen_server:call(RoomPid, room_message).

start_party(RoomPid, FromID) ->
    gen_server:call(RoomPid, {start_party, FromID}).

dismiss_party(RoomPid, FromID) ->
    gen_server:call(RoomPid, {dismiss_party, FromID}).

join_room(RoomPid, FromID, CharInfo) ->
    gen_server:call(RoomPid, {join_room, FromID, CharInfo}).

quit_room(RoomPid, FromID) ->
    gen_server:call(RoomPid, {quit_room, FromID}).

kick_member(RoomPid, FromID, TargetID) ->
    gen_server:call(RoomPid, {kick_member, FromID, TargetID}).

buy_check(RoomPid, FromID, BuyID) ->
    gen_server:call(RoomPid, {buy_check, FromID, BuyID}).

buy_done(RoomPid, FromID, BuyID, BuyName, ItemName) ->
    gen_server:cast(RoomPid, {buy_done, FromID, BuyID, BuyName, ItemName}).

chat(RoomPid, FromID, Content) ->
    gen_server:cast(RoomPid, {chat, FromID, Content}).

kill_room_by_char_id(CharID) ->
    case dj_global:find_char_party_room_pid(CharID) of
        {ok, RoomPid} -> gen_server:call(RoomPid, kill_room);
        Error -> Error
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #room{}} | {ok, State :: #room{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([ServerID, OwnerID, CharInfo, RoomLevel]) ->
    Member = #room_member{
        char_id = OwnerID, joined_at = arrow:timestamp(),
        info = CharInfo, buy_info = #{}
    },

    Seats = #{1 => Member, 2 => undefined, 3 => undefined},

    State = #room{
        sid = ServerID, owner = OwnerID, level = RoomLevel,
        seats = Seats,
        messages = [],
        create_at = arrow:timestamp(),
        start_at = 0
    },

    dj_global:register_party_room(),
    dj_global:register_char_party_room(OwnerID),

    lager:info("Party room created by " ++ integer_to_list(OwnerID)),
    gen_server:cast(self(), broadcast_party_notify),
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #room{}) ->
    {reply, Reply :: term(), NewState :: #room{}} |
    {reply, Reply :: term(), NewState :: #room{}, timeout() | hibernate} |
    {noreply, NewState :: #room{}} |
    {noreply, NewState :: #room{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #room{}} |
    {stop, Reason :: term(), NewState :: #room{}}).

handle_call(party_info, _From, State) ->
    {reply, make_proto_party_info(State), State};

handle_call(simple_party_info, _From, #room{level = Lv, seats = Seats, start_at = At} = State) ->
    #{1 := Owner} = Seats,
    #{name := Name} = Owner#room_member.info,

    Amount = get_member_amount(Seats),

    % {ok, owner_id, owner_name, level, amount, start_at}
    Reply = {ok, Owner#room_member.char_id, Name, Lv, Amount, At},
    {reply, Reply, State};

handle_call(room_message, _From, #room{messages = Messages} = State) ->
    Reply = make_proto_party_message(Messages),
    {reply, Reply, State};

%% ==================

handle_call({start_party, FromID}, _From, #room{owner = Owner} = State) when FromID =/= Owner ->
    Reply = {error, "party only owner can start party", ?ERROR_CODE_PARTY_NOT_OWNER},
    {reply, Reply, State};

handle_call({start_party, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, "party can not start already started", ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({start_party, _}, _From, #room{owner = Owner, level = Lv, seats = Seats} = State) ->
    case get_member_amount(Seats) =:= 1 of
        true ->
            Reply = {error, "party cannot start no members", ?ERROR_CODE_PARTY_CANNOT_START_NO_MEMBERS},
            {reply, Reply, State};
        false ->
            erlang:send_after(?ROOM_SURVIVAL_TIME, self(), party_end),

            CharIDS = get_member_char_ids(Seats),
            JoinMembers = lists:delete(Owner, CharIDS),
            PartyProto = make_proto_party_info(State),

            gen_cast_to_members([Owner], {party_start, create, PartyProto}, {}),
            gen_cast_to_members(JoinMembers, {party_start, join, PartyProto}, {}),

            lager:info("Party started. Owner: " ++ integer_to_list(Owner)),
            {reply, {ok, Lv, JoinMembers}, State#room{start_at = arrow:timestamp()}}
    end;

%% ==================

handle_call({dismiss_party, FromID}, _From, #room{owner = Owner} = State) when FromID =/= Owner ->
    Reply = {error, "party only owner can dismiss party", ?ERROR_CODE_PARTY_NOT_OWNER},
    {reply, Reply, State};

handle_call({dismiss_party, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, "party can not dismiss already started", ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({dismiss_party, _}, _From, #room{owner = Owner, seats = Seats} = State) ->
    CharIDS = get_member_char_ids(Seats),
    gen_cast_to_members(CharIDS, party_dismiss, {dj_global, unregister_char_party_room, []}),
    lager:info("Party dismissed. Owner: " ++ integer_to_list(Owner)),
    {stop, normal, State};

%% ==================


handle_call({join_room, Owner, _}, _From, #room{owner = Owner} = State) ->
    Reply = {error, "party can not join self room", ?ERROR_CODE_PARTY_CANNOT_JOIN_SELF_ROOM},
    {reply, Reply, State};

handle_call({join_room, _, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, "party can not join already started", ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({join_room, FromID, CharInfo}, _From, #room{owner = Owner, seats = Seats, messages = Message} = State) ->
    EmptySeats = get_empty_seats(Seats),
    case maps:size(EmptySeats) =:= 0 of
        true ->
            Reply = {error, "party can not join full", ?ERROR_CODE_PARTY_CANNOT_JOIN_FULL},
            {reply, Reply, State};
        false ->
            SeatID = lists:min(maps:keys(EmptySeats)),
            Member = #room_member{char_id = FromID,
                joined_at = arrow:timestamp(),
                info = CharInfo,
                buy_info = #{}},

            dj_global:register_char_party_room(FromID),
            gen_server:cast(self(), broadcast_party_notify),

            #{name := Name} = CharInfo,
            NewMsg = generate_party_message(3, [Name]),

            lager:info("Party " ++ integer_to_list(FromID) ++ " joined. Owner: " ++ integer_to_list(Owner)),

            {reply, ok, State#room{seats = Seats#{SeatID := Member}, messages = [NewMsg | Message]}}
    end;


handle_call({quit_room, Owner}, _From, #room{owner = Owner} = State) ->
    Reply = {error, "party owner can not quit", ?ERROR_CODE_PARTY_OWNER_CANNOT_QUIT},
    {reply, Reply, State};

handle_call({quit_room, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, "party can not quit already started", ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({quit_room, FromID}, _From, #room{owner = Owner, seats = Seats, messages = Messages} = State) ->
    {SeatID, Info} = find_seat_id_by_char_id(maps:to_list(Seats), FromID),
    NewSeats = Seats#{SeatID := undefined},

    dj_global:unregister_char_party_room(FromID),
    gen_cast_to_members([FromID], party_quit, {}),
    gen_server:cast(self(), broadcast_party_notify),

    #{name := Name} = Info,
    NewMsg = generate_party_message(4, [Name]),

    lager:info("Party " ++ integer_to_list(FromID) ++ " quit. Owner: " ++ integer_to_list(Owner)),

    {reply, ok, State#room{seats = NewSeats, messages = [NewMsg | Messages]}};

%% ==================

handle_call({kick_member, FromID, _}, _From, #room{owner = Owner} = State) when FromID =/= Owner ->
    Reply = {error, "party can not kick not owner", ?ERROR_CODE_PARTY_NOT_OWNER},
    {reply, Reply, State};

handle_call({kick_member, FromID, FromID}, _From, State) ->
    Reply = {error, "party can not kick self", ?ERROR_CODE_PARTY_CANNOT_KICK_SELF},
    {reply, Reply, State};

handle_call({kick_member, _, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, "party can not kick already started", ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({kick_member, _, TargetID}, _From, #room{owner = Owner, seats = Seats} = State) ->
    case find_seat_id_by_char_id(maps:to_list(Seats), TargetID) of
        undefined ->
            Reply = {error, "party not member. cannot kick", ?ERROR_CODE_INVALID_OPERATE},
            {reply, Reply, State};
        {SeatID, _Info} ->
            dj_global:unregister_char_party_room(TargetID),
            gen_cast_to_members([TargetID], party_been_kicked, {}),
            gen_server:cast(self(), broadcast_party_notify),

            NewSeats = Seats#{SeatID := undefined},

            lager:info("Party " ++ integer_to_list(TargetID) ++ " beed kicked. Owner: " ++ integer_to_list(Owner)),

            {reply, ok, State#room{seats = NewSeats}}
    end;

handle_call({buy_check, _FromID, _BuyID},  _From, #room{start_at = 0} = State) ->
    Reply = {error, "party not start can not buy", ?ERROR_CODE_PARTY_NOT_STARTED},
    {reply, Reply, State};

handle_call({buy_check, FromID, BuyID}, _From, #room{level = Lv, seats = Seats} = State) ->
    #{FromID := #room_member{buy_info = BuyInfo}} = Seats,

    OtherMembers = lists:delete(FromID, get_member_char_ids(Seats)),

    Reply =
    case maps:find(BuyID, BuyInfo) of
        error ->
            {ok, Lv, OtherMembers};
        {ok, Value} ->
            case Value >= 10 of
                true ->
                    {error, "party no buy times", ?ERROR_CODE_PARTY_NO_BUY_TIMES};
                false ->
                    {ok, Lv, OtherMembers}
            end
    end,

    {reply, Reply, State};

handle_call(kill_room, _From, #room{seats = Seats} = State) ->
    CharIDS = get_member_char_ids(Seats),
    gen_cast_to_members(CharIDS, party_dismiss, {dj_global, unregister_char_party_room, []}),
    lager:warning("Party Killed"),
    {stop, normal, kill_done, State}.

%% ==================


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #room{}) ->
    {noreply, NewState :: #room{}} |
    {noreply, NewState :: #room{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #room{}}).

handle_cast({buy_done, FromID, BuyID, BuyName, ItemName},
    #room{seats = Seats, messages = Messages} = State) ->

    #{FromID := Member} = Seats,
    #{name := Name} = Member#room_member.info,

    % update buy info
    BuyInfo = Member#room_member.buy_info,

    OldValue =
    case maps:find(BuyID, BuyInfo) of
        error -> 0;
        {ok, Value} -> Value
    end,

    BuyInfo1 = BuyInfo#{BuyID => OldValue+1},
    Member1 = Member#room_member{buy_info = BuyInfo1},
    Seats1 = Seats#{FromID := Member1},

    NewMsg = generate_party_message(2, [Name, BuyName, ItemName]),
    {noreply, State#room{seats = Seats1, messages = [NewMsg | Messages]}};


handle_cast({chat, FromID, Content}, #room{seats = Seats, messages = Messages} = State) ->
    #{FromID := Member} = Seats,
    #{name := Name} = Member#room_member.info,

    NewMsg = generate_party_message(1, [Name, Content]),
    {noreply, State#room{messages = [NewMsg | Messages]}};

handle_cast(broadcast_party_notify, #room{seats = Seats} = State) ->
    PartyProto = make_proto_party_info(State),
    CharIDs = get_member_char_ids(Seats),

    gen_cast_to_members(CharIDs, {send_party_notify, PartyProto}, {}),
    {noreply, State};

handle_cast({broadcast_msgbin, MsgBin}, #room{seats = Seats} = State) ->
    CharIDs = get_member_char_ids(Seats),
    gen_cast_to_members(CharIDs, {send_msg, MsgBin}, {}),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #room{}) ->
    {noreply, NewState :: #room{}} |
    {noreply, NewState :: #room{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #room{}}).
handle_info(party_end, #room{sid = SID, owner = Owner, level = Lv, seats = Seats} = State) ->
    lager:info("Party End. Owner: " ++ integer_to_list(Owner)),

    JoinMembers = lists:delete(Owner, get_member_char_ids(Seats)),

    Req = json:to_binary(#{
        server_id => SID,
        char_id => Owner,
        party_level => Lv,
        member_ids => JoinMembers
    }),

    OwnerPid =
    case dj_global:find_char_pid(Owner) of
        {error, _} -> undefined;
        {ok, Pid} -> Pid
    end,

    dj_http_client:api_response_handle(
        party_end,
        Req,
        {?MODULE, succeed_callback_party_end, [State]},
        OwnerPid
    ),

    {stop, normal, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #room{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #room{},
    Extra :: term()) ->
    {ok, NewState :: #room{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

succeed_callback_party_end([#{<<"talent_id">> := Talent},
    #room{owner = Owner, seats = Seats} = State]) ->

    case dj_global:find_char_pid(Owner) of
        {error, _} -> ok;
        {ok, Pid} -> gen_server:cast(Pid, {set_party_talent_id, Talent})
    end,

    CharIDS = get_member_char_ids(Seats),
    gen_cast_to_members(CharIDS, party_end, {dj_global, unregister_char_party_room, []}),
    {ok, State}.

%% =============================

get_member_amount(Seats) ->
    M = maps:filter(fun(_K, V) -> V =/= undefined end, Seats),
    maps:size(M).

get_member_char_ids(Seats) ->
    Fun = fun(_, V, Acc) ->
            case V of
                undefined ->
                    Acc;
                _ ->
                    [V#room_member.char_id | Acc]
            end
          end,

    maps:fold(Fun, [], Seats).


get_empty_seats(Seats) ->
    maps:filter(fun(_K, V) -> V =:= undefined end, Seats).

find_seat_id_by_char_id([], _) ->
    undefined;

find_seat_id_by_char_id([{_SeatID, undefined} | Rest], CharID) ->
    find_seat_id_by_char_id(Rest, CharID);

find_seat_id_by_char_id([{SeatID, #room_member{char_id = CharID, info = Info}} | _Rest], CharID) ->
    {SeatID, Info};

find_seat_id_by_char_id([_Header | Rest], CharID) ->
    find_seat_id_by_char_id(Rest, CharID).


%% ==============================

make_proto_msg_party_member_buy_info(BuyInfo) ->
    Fun = fun({Id, Times}, Acc) ->
            Msg = #'ProtoPartyInfo.PartyMember.BuyInfo'{buy_id = Id, buy_times = Times},
            [Msg | Acc]
          end,

    lists:foldl(Fun, [], maps:to_list(BuyInfo)).

make_proto_msg_party_member(Seats) ->
    Fun = fun({SeatID, Member}, Acc) ->
                Msg =
                case Member of
                    undefined ->
                        #'ProtoPartyInfo.PartyMember'{
                            id = <<>>,
                            flag = 0,
                            name = <<>>,
                            seat_id = SeatID,
                            buy_info = []
                        };
                    _ ->
                        #{flag := Flag, name := Name} = Member#room_member.info,

                        #'ProtoPartyInfo.PartyMember'{
                            id = integer_to_binary(Member#room_member.char_id),
                            flag = Flag,
                            name = Name,
                            seat_id = SeatID,
                            buy_info = make_proto_msg_party_member_buy_info(Member#room_member.buy_info)
                        }
                end,

                [Msg | Acc]
          end,

    lists:foldl(Fun, [], maps:to_list(Seats)).

make_proto_party_info(Lv, At, Seats) ->
    EndAt =
        if
            At > 0 -> At + ?ROOM_SURVIVAL_TIME;
            true -> 0
        end,

    #'ProtoPartyInfo'{
        level = Lv,
        end_at = EndAt,
        members = make_proto_msg_party_member(Seats)
    }.


make_proto_party_info(#room{level = Lv, start_at = At, seats = Seats}) ->
    make_proto_party_info(Lv, At, Seats).


make_proto_party_message(Messages) when is_list(Messages) ->
    Fun = fun(#room_message{tp = Tp, args = Args}, Acc) ->
            Msg = make_single_proto_party_message(Tp, Args),
            [Msg | Acc]
          end,

    #'ProtoPartyMessageNotify'{
        session = <<>>,
        act = 'ACT_INIT',
        messages = lists:foldl(Fun, [], lists:reverse(Messages))
    }.

make_proto_party_message(tp, args) ->
    #'ProtoPartyMessageNotify'{
        session = <<>>,
        act = 'ACT_UPDATE',
        messages = [make_single_proto_party_message(tp, args)]
    }.

make_single_proto_party_message(tp, args) ->
    #'ProtoPartyMessageNotify.PartyMessage'{
        tp = tp,
        args = args
    }.

generate_party_message(Tp, Args) ->
    Notify = make_proto_party_message(Tp, Args),
    MsgBin = dj_protocol_handler:encode_message(Notify),
    gen_server:cast(self(), {broadcast_msgbin, MsgBin}),
    #room_message{tp = Tp, args = Args}.

gen_cast_to_members(CharIDs, Message, FunctionOnCharID) ->
    Fun = fun(CID) ->
            case FunctionOnCharID of
                {M, F, A} -> apply(M, F, [CID | A]);
                {} -> ok
            end,

            case dj_global:find_char_pid(CID) of
                {error, _} -> ok;
                {ok, Pid} -> gen_server:cast(Pid, Message)
            end
          end,

    lists:foreach(Fun, CharIDs).