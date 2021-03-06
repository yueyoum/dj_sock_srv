%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Sep 2016 下午5:03
%%%-------------------------------------------------------------------
-module(dj_client).
-author("wang").

-behaviour(gen_server).
-behaviour(ranch_protocol).

%% API
-export([start_link/4,
    response/3]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-include("dj_player.hrl").
-include("dj_error_code.hrl").
-include("dj_protocol.hrl").

-define(SERVER, ?MODULE).
-define(ACTIVE, 10).
-define(CLIENT_TIMEOUT, 1000 * 3600).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
start_link(Ref, Socket, Transport, Opts) ->
    gen_server:start_link(?SERVER, [Ref, Socket, Transport, Opts], []).

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
    {ok, State :: #client_state{}} | {ok, State :: #client_state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([Ref, Socket, Transport, _Opts]) ->
    put(init, true),
    {OK, Closed, Error} = Transport:messages(),
    ok = Transport:setopts(Socket, [{active, ?ACTIVE}, {packet, 4}]),

    State = #client_state{ref = Ref, socket = Socket, transport = Transport,
        ok = OK, closed = Closed, error = Error,
        server_id = 0, char_id = 0, info = #{},
        party_room_pid = undefined,
        party_remained_create_times = 0,
        party_remained_join_times = 0,
        party_talent_id = 0,
        party_max_buy_times = 0},

    {ok, State, 0}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #client_state{}) ->
    {reply, Reply :: term(), NewState :: #client_state{}} |
    {reply, Reply :: term(), NewState :: #client_state{}, timeout() | hibernate} |
    {noreply, NewState :: #client_state{}} |
    {noreply, NewState :: #client_state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #client_state{}} |
    {stop, Reason :: term(), NewState :: #client_state{}}).
handle_call(shutdown, _From, #client_state{char_id = CharID} = State) ->
    try
        dj_global:unregister_char(CharID)
    catch
        _ -> ok
    end,

    lager:warning("CharID ~p process are shutdown by server", [CharID]),
    {stop, normal, shutdown_ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #client_state{}) ->
    {noreply, NewState :: #client_state{}} |
    {noreply, NewState :: #client_state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #client_state{}}).
handle_cast(send_login_notify,
    #client_state{socket = Socket, transport = Transport, char_id = CharID} = State) ->
    RoomKey = dj_utils:char_id_to_party_room_key(CharID),
    RoomPid = gproc:where({n, g, RoomKey}),

    PartyProto = dj_party_room:get_room_info(RoomPid),
    MessageProto = dj_party_room:get_room_message(RoomPid),

    send_party_info_notify(PartyProto, State),
    response(Transport, Socket, MessageProto),
    {noreply, State, ?CLIENT_TIMEOUT};

handle_cast({party_start, create, PartyProto}, #client_state{party_remained_create_times = CT} = State) ->
    State1 = State#client_state{party_remained_create_times = CT-1},
    send_party_info_notify(PartyProto, State1),
    {noreply, State1, ?CLIENT_TIMEOUT};

handle_cast({party_start, join, PartyProto}, #client_state{party_remained_join_times = JT} = State) ->
    State1 = State#client_state{party_remained_join_times = JT-1},
    send_party_info_notify(PartyProto, State1),
    {noreply, State1, ?CLIENT_TIMEOUT};

handle_cast(party_dismiss, #client_state{socket = Socket, transport = Transport} = State) ->
    error_response(Transport, Socket, ?ERROR_CODE_PARTY_DISMISS),
    send_party_info_notify(undefined, State),
    % clean message
    response(Transport, Socket, dj_party_room:get_room_message(undefined)),
    {noreply, State#client_state{party_room_pid = undefined}, ?CLIENT_TIMEOUT};

handle_cast(party_quit, #client_state{socket = Socket, transport = Transport} = State) ->
    send_party_info_notify(undefined, State),
    response(Transport, Socket, dj_party_room:get_room_message(undefined)),
    {noreply, State#client_state{party_room_pid = undefined}, ?CLIENT_TIMEOUT};

handle_cast(party_been_kicked, #client_state{socket = Socket, transport = Transport} = State) ->
    error_response(Transport, Socket, ?ERROR_CODE_PARTY_BEEN_KICKED),
    send_party_info_notify(undefined, State),
    response(Transport, Socket, dj_party_room:get_room_message(undefined)),
    {noreply, State#client_state{party_room_pid = undefined}, ?CLIENT_TIMEOUT};

handle_cast({send_party_notify, PartyProto}, State) ->
    send_party_info_notify(PartyProto, State),
    {noreply, State, ?CLIENT_TIMEOUT};

handle_cast({send_msg, Msgs}, #client_state{socket = Socket, transport = Transport} = State) ->
    Fun = fun(M) -> response(Transport, Socket, M) end,
    lists:foreach(Fun, Msgs),
    {noreply, State, ?CLIENT_TIMEOUT};

handle_cast({set_party_talent_id, Talent}, State) ->
    {noreply, State#client_state{party_talent_id = Talent}, ?CLIENT_TIMEOUT};

handle_cast(party_end, #client_state{socket = Socket, transport = Transport} = State) ->
    error_response(Transport, Socket, ?ERROR_CODE_PARTY_END),
    send_party_info_notify(undefined, State),
    response(Transport, Socket, dj_party_room:get_room_message(undefined)),
    {noreply, State#client_state{party_room_pid = undefined}, ?CLIENT_TIMEOUT}.

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
-spec(handle_info(Info :: timeout() | term(), State :: #client_state{}) ->
    {noreply, NewState :: #client_state{}} |
    {noreply, NewState :: #client_state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #client_state{}}).
handle_info({OK, Socket, <<ID:32, MsgBin/binary>>},
    #client_state{socket = Socket, transport = Transport, ok = OK} = State) ->

    Name = dj_protocol_mapping:get_name(ID),
    lager:info("Socket recv: ~p, ~p", [ID, Name]),

    case process_msg(Name, MsgBin, State) of
        {ok, NewState} ->
            {noreply, NewState, ?CLIENT_TIMEOUT};
        {error, Reason} ->
            error_response(Transport, Socket),
            lager:error("Process msg Error: ~p", [Reason]),
            {stop, normal, State};
        {error, Reason, ErrorCode} ->
            lager:warning("Warn: ~p, ~p", [ErrorCode, Reason]),
            error_response(Transport, Socket, ErrorCode),
            {noreply, State, ?CLIENT_TIMEOUT}
    end;

handle_info({OK, Socket, _Data}, #client_state{socket = Socket, transport = Transport, ok = OK} = State) ->
    lager:error("Socket recv bag data"),
    error_response(Transport, Socket),
    {stop, normal, State};

handle_info({Closed, Socket}, #client_state{socket = Socket, closed = Closed}=State) ->
    lager:info("Socket closed"),
    {stop, normal, State};

handle_info({Error, Socket, Reason}, #client_state{socket = Socket, error = Error}=State) ->
    lager:error("Socket error"),
    {stop, Reason, State};

handle_info({tcp_passive, Socket}, #client_state{socket = Socket, transport = Transport}=State) ->
    io:format("Socket Passive!~n"),
    %% TODO
    Transport:setopts(Socket, [{active, ?ACTIVE}]),
    {noreply, State, ?CLIENT_TIMEOUT};

handle_info(timeout, #client_state{ref = Ref, socket = Socket, transport = Transport} = State) ->
    case get(init) of
        true ->
            % do init stuffs
            {ok, {Ip, _Port}} = Transport:peername(Socket),
            lager:info("New Connection From ~p", [inet_parse:ntoa(Ip)]),
            ok = ranch:accept_ack(Ref),
            erase(init),

            case dj_party_room:is_party_open() of
                true ->
                    {noreply, State, ?CLIENT_TIMEOUT};
                false ->
                    lager:warning("Party Not Open, Close Connection"),
                    {stop, normal, State}
            end;
        undefined ->
            lager:info("Client timeout"),
            {stop, normal, State}
    end.



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
    State :: #client_state{}) -> term()).
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
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #client_state{},
    Extra :: term()) ->
    {ok, NewState :: #client_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec process_msg(Name, binary(), #client_state{}) ->
    {ok, #client_state{}} |
    {error, term()} |
    {error, term(), integer()}
    when Name :: atom() | undefined.
process_msg(undefined, _MsgBin, _State) ->
    {error, "Unkown Msg ID"};

process_msg(Name, MsgBin, State) ->
    try dj_protocol:decode_msg(MsgBin, Name) of
        Msg ->
            dj_protocol_handler:handle(Msg, State)
    catch error:Reason ->
        {error, Reason}
    end.

send_party_info_notify(PartyProto,
    #client_state{socket = Socket, transport = Transport,
        party_remained_create_times = CT,
        party_remained_join_times = JT,
        party_talent_id = Talent}) ->

    Msg = #'ProtoPartyInfoNotify'{
        session = <<>>,
        talent_id = Talent,
        talent_end_at = tomorrow_time(12),
        remained_create_times = CT,
        remained_join_times = JT,
        info = PartyProto
    },

    response(Transport, Socket, Msg).


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
    case Transport:send(Socket, MsgBin) of
        ok -> ok;
        {error, Reason} ->
            lager:warning("Socket Send Error: ~p", [Reason])
    end;

response(Transport, Socket, Msg) ->
    response(Transport, Socket, dj_protocol_handler:encode_message(Msg)).


tomorrow_time(Hour) ->
    {ok, Tz} = application:get_env(dj_sock_srv, time_zone),

    {Date, {HH, _, _}} = arrow:add_hours(arrow:timestamp(), Tz),

    T1 =
    case HH >= Hour of
        true ->
            arrow:add_days({Date, {Hour, 0, 0}}, 1);
        false ->
            {Date, {Hour, 0, 0}}
    end,

    T2 = arrow:add_hours(T1, -Tz),
    arrow:timestamp(T2).
