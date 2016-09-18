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
    reg_char_room_key/1,
    unreg_char_room_key/1,
    get_info/1,
    start_party/2,
    dismiss_party/2,
    join_room/3,
    quit_room/2,
    kick_member/3,
    chat/3,
    buy/3]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-include("dj_protocol.hrl").
-include("dj_error_code.hrl").

-record(room_message, {
    tp          :: pos_integer(),
    msg         :: [string()]
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

-define(ROOM_SURVIVAL_TIME, 1000 * 60).

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


reg_char_room_key(CharID) ->
    true = gproc:reg({n, g, dj_utils:char_id_to_party_room_key(CharID)}).

unreg_char_room_key(CharID) ->
    true = gproc:unreg({n, g, dj_utils:char_id_to_party_room_key(CharID)}).


get_info(RoomPid) ->
    gen_server:call(RoomPid, party_info).

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

chat(RoomPid, FromID, Content) ->
    gen_server:cast(RoomPid, {chat, FromID, Content}).

buy(RoomPid, FromID, BuyID) ->
    gen_server:cast(RoomPid, {buy, FromID, BuyID}).


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

    % register self
    true = gproc:reg({p, g, party_room}),
    reg_char_room_key(OwnerID),

    gen_server:cast(self(), {broadcast, undefined, {}}),
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
    {reply, make_proto_msg_party(State), State};

%% ==================

handle_call({start_party, FromID}, _From, #room{owner = Owner} = State) when FromID =/= Owner ->
    Reply = {error, <<"only owner can start party">>, ?ERROR_CODE_PARTY_NOT_OWNER},
    {reply, Reply, State};

handle_call({start_party, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, <<"can not start already started">>, ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({start_party, _}, _From, #room{seats = Seats} = State) ->
    case get_member_amount(Seats) =:= 1 of
        true ->
            Reply = {error, <<"party cannot start no members">>, ?ERROR_CODE_PARTY_CANNOT_START_NO_MEMBERS},
            {reply, Reply, State};
        false ->
            erlang:send_after(?ROOM_SURVIVAL_TIME, self(), party_end),
            gen_server:cast(self(), {broadcast, undefined, {}}),
            {reply, ok, State#room{start_at = arrow:timestamp()}}
    end;

%% ==================

handle_call({dismiss_party, FromID}, _From, #room{owner = Owner} = State) when FromID =/= Owner ->
    Reply = {error, <<"only owner can dismiss party">>, ?ERROR_CODE_PARTY_NOT_OWNER},
    {reply, Reply, State};

handle_call({dismiss_party, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, <<"can not dismiss already started">>, ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({dismiss_party, _}, _From, #room{seats = Seats} = State) ->
    CharIDS = get_member_char_ids(Seats),
    gen_cast_to_members(CharIDS, party_dismiss, {?MODULE, unreg_char_room_key, []}),
    {stop, normal, State};

%% ==================


handle_call({join_room, Owner, _}, _From, #room{owner = Owner} = State) ->
    Reply = {error, <<"can not join self room">>, ?ERROR_CODE_PARTY_CANNOT_JOIN_SELF_ROOM},
    {reply, Reply, State};

handle_call({join_room, _, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, <<"can not join already started">>, ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({join_room, FromID, CharInfo}, _From, #room{seats = Seats} = State) ->
    EmptySeats = get_empty_seats(Seats),
    case maps:size(EmptySeats) =:= 0 of
        true ->
            Reply = {error, <<"can not join full">>, ?ERROR_CODE_PARTY_CANNOT_JOIN_FULL},
            {reply, Reply, State};
        false ->
            SeatID = lists:min(maps:keys(EmptySeats)),
            Member = #room_member{char_id = FromID,
                joined_at = arrow:timestamp(),
                info = CharInfo,
                buy_info = #{}},

            % register
            reg_char_room_key(FromID),
            gen_server:cast(self(), {broadcast, undefined, {}}),

            {reply, ok, State#room{seats = Seats#{SeatID := Member}}}
    end;

%% ==================


handle_call({quit_room, Owner}, _From, #room{owner = Owner} = State) ->
    Reply = {error, <<"owner can not quit">>, ?ERROR_CODE_PARTY_OWNER_CANNOT_QUIT},
    {reply, Reply, State};

handle_call({quit_room, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, <<"can not quit already started">>, ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({quit_room, FromID}, _From, #room{seats = Seats} = State) ->
    SeatID = find_seat_id_by_char_id(maps:to_list(Seats), FromID),
    NewSeats = Seats#{SeatID := undefined},

    % un-register
    unreg_char_room_key(FromID),
    gen_cast_to_members([FromID], party_quit, {}),
    gen_server:cast(self(), {broadcast, FromID, {}}),

    {reply, ok, State#room{seats = NewSeats}};

%% ==================

handle_call({kick_member, FromID, _}, _From, #room{owner = Owner} = State) when FromID =/= Owner ->
    Reply = {error, <<"can not kick not owner">>, ?ERROR_CODE_PARTY_NOT_OWNER},
    {reply, Reply, State};

handle_call({kick_member, FromID, FromID}, _From, State) ->
    Reply = {error, <<"can not kick self">>, ?ERROR_CODE_PARTY_CANNOT_KICK_SELF},
    {reply, Reply, State};

handle_call({kick_member, _, _}, _From, #room{start_at = At} = State) when At > 0 ->
    Reply = {error, <<"can not kick already started">>, ?ERROR_CODE_PARTY_HAS_STARTED},
    {reply, Reply, State};

handle_call({kick_member, _, TargetID}, _From, #room{seats = Seats} = State) ->
    case find_seat_id_by_char_id(maps:to_list(Seats), TargetID) of
        undefined ->
            Reply = {error, <<"not member. cannot kick">>, ?ERROR_CODE_INVALID_OPERATE},
            {reply, Reply, State};
        SeatID ->
            unreg_char_room_key(TargetID),
            gen_cast_to_members([TargetID], party_been_kicked, {}),
            gen_server:cast(self(), {broadcast, TargetID, {}}),

            NewSeats = Seats#{SeatID := undefined},
            {reply, ok, State#room{seats = NewSeats}}
    end.

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

handle_cast({chat, _FromID, _Content}, #room{seats = _Seats, messages = _Messages} = State) ->
    {noreply, State};

handle_cast({buy, _FromID, _BuyID}, #room{seats = _Seats, messages = _Messages} = State) ->
    {noreply, State};

handle_cast({broadcast, Exclude, FunctionOnCharID}, #room{seats = Seats} = State) ->
    PartyProto = make_proto_msg_party(State),
    CharIDs = lists:delete(Exclude, get_member_char_ids(Seats)),

    gen_cast_to_members(CharIDs, {send_party_notify, PartyProto}, FunctionOnCharID),
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
handle_info(party_end, #room{seats = Seats} = State) ->
    io:format("party_end~n"),
    CharIDS = get_member_char_ids(Seats),
    gen_cast_to_members(CharIDS, party_end, {?MODULE, unreg_char_room_key, []}),
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

find_seat_id_by_char_id([{SeatID, #room_member{char_id = CharID}} | _Rest], CharID) ->
    SeatID;

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
                case Member of
                    undefined -> Acc;
                    _ ->
                        #{flag := Flag, name := Name} = Member#room_member.info,

                        Msg = #'ProtoPartyInfo.PartyMember'{
                            id = integer_to_binary(Member#room_member.char_id),
                            flag = Flag,
                            name = Name,
                            seat_id = SeatID,
                            buy_info = make_proto_msg_party_member_buy_info(Member#room_member.buy_info)
                        },

                        [Msg | Acc]
                end
          end,

    lists:foldl(Fun, [], maps:to_list(Seats)).

make_proto_msg_party(Lv, At, Seats) ->
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


make_proto_msg_party(#room{level = Lv, start_at = At, seats = Seats}) ->
    make_proto_msg_party(Lv, At, Seats).


gen_cast_to_members(CharIDs, Message, FunctionOnCharID) ->
    Fun = fun(CID) ->
            case FunctionOnCharID of
                {M, F, A} -> apply(M, F, [CID | A]);
                {} -> ok
            end,

            CharPid = gproc:where({n, g, dj_utils:char_id_to_binary_id(CID)}),
            case CharPid of
                undefined -> ok;
                _ ->
                    gen_server:cast(CharPid, Message)
            end
          end,

    lists:foreach(Fun, CharIDs).