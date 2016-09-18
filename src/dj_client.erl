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

%% API
-export([start_link/4,
    party_info/1,
    make_party_notify/1,
    party_open_range/2]).

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
    proc_lib:start_link(?SERVER, init, [[Ref, Socket, Transport, Opts]]).

party_info(CharID) ->
    RoomKey = dj_utils:char_id_to_party_room_key(CharID),
    RoomPid = gproc:where({n, g, RoomKey}),

    if
        RoomPid =:= undefined -> undefined;
        true -> gen_server:call(RoomPid, party_info)
    end.

make_party_notify(_CharID) ->
    ok.

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
    io:format("NEW CONNECTION~n"),

    ok = proc_lib:init_ack({ok, self()}),
    ok = ranch:accept_ack(Ref),
    ok = Transport:setopts(Socket, [{active, ?ACTIVE}, {packet, 4}]),

    {OK, Closed, Error} = Transport:messages(),

    State = #client_state{ref = Ref, socket = Socket, transport = Transport,
        ok = OK, closed = Closed, error = Error,
        server_id = 0, char_id = 0, info = #{},
        party_room_pid = undefined},

    gen_server:enter_loop(?SERVER, [], State).
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
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

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
handle_cast(party_dismiss, #client_state{socket = Socket, transport = Transport} = State) ->
    dj_protocol_handler:error_response(Transport, Socket, ?ERROR_CODE_PARTY_DISMISS),
    send_party_notify(Transport, Socket, undefined),
    {noreply, State#client_state{party_room_pid = undefined}};

handle_cast(party_quit, #client_state{socket = Socket, transport = Transport} = State) ->
    send_party_notify(Transport, Socket, undefined),
    {noreply, State#client_state{party_room_pid = undefined}};

handle_cast(party_been_kicked, #client_state{socket = Socket, transport = Transport} = State) ->
    dj_protocol_handler:error_response(Transport, Socket, ?ERROR_CODE_PARTY_BEEN_KICKED),
    send_party_notify(Transport, Socket, undefined),
    {noreply, State#client_state{party_room_pid = undefined}};

handle_cast({send_party_notify, PartyProto},
    #client_state{socket = Socket, transport = Transport} = State) ->
    send_party_notify(Transport, Socket, PartyProto),
    {noreply, State};

handle_cast(party_end, #client_state{socket = Socket, transport = Transport} = State) ->
    dj_protocol_handler:error_response(Transport, Socket, ?ERROR_CODE_PARTY_END),
    send_party_notify(Transport, Socket, undefined),
    {noreply, State#client_state{party_room_pid = undefined}}.

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
    io:format("RECV: ~p ~p~n", [ID, Name]),

    case process_msg(Name, MsgBin, State) of
        {ok, NewState} ->
            io:format("NewState: ~p~n", [NewState]),
            {noreply, NewState};
        {error, Reason} ->
            dj_protocol_handler:error_response(Transport, Socket),
            {stop, Reason, State};
        {error, Reason, ErrorCode} ->
            io:format("WARING: ~p~n", [Reason]),
            dj_protocol_handler:error_response(Transport, Socket, ErrorCode),
            {noreply, State}
    end;

handle_info({OK, Socket, _}, #client_state{socket = Socket, transport = Transport, ok = OK} = State) ->
    io:format("RECV Error Data~n"),
    dj_protocol_handler:error_response(Transport, Socket),
    {stop, normal, State};

handle_info({Closed, Socket}, #client_state{socket = Socket, closed = Closed}=State) ->
    io:format("Socket Closed~n"),
    {stop, normal, State};

handle_info({Error, Socket, Reason}, #client_state{socket = Socket, error = Error}=State) ->
    io:format("Socket Error. Reason: ~p~n", [Reason]),
    {stop, Reason, State};

handle_info({tcp_passive, Socket}, #client_state{socket = Socket, transport = Transport}=State) ->
    io:format("Socket Passive!~n"),
    %% TODO
    Transport:setopts(Socket, [{active, ?ACTIVE}]),
    {noreply, State};

handle_info(timeout, State) ->
    io:format("TIMEOUT~n"),
    {stop, timeout, State}.


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

process_msg(undefined, _MsgBin, _State) ->
    {error, <<"Unkown Msg ID">>};

process_msg(Name, MsgBin, State) ->
    try dj_protocol:decode_msg(MsgBin, Name) of
        Msg ->
            io:format("MSG: ~p~n", [Msg]),
            dj_protocol_handler:handle(Msg, State)
    catch error:Reason ->
        {error, Reason}
    end.


send_party_notify(Transport, Socket, PartyProto) ->
    {OpenAt, CloseAt} = party_open_range(0, 23),

    TEndAt = arrow:add_hours(arrow:timestamp(), 5),


    Msg = #'ProtoPartyNotify'{
        session = <<>>,
        open_at = OpenAt,
        close_at = CloseAt,
        talent_id = 0,
        talent_end_at = arrow:timestamp(TEndAt),
        remained_create_times = 1,
        remained_join_times = 1,
        info = PartyProto
    },

    dj_protocol_handler:response(Transport, Socket, Msg).


party_open_range(H1, H2) ->
    {{Y, M, D}, _} = arrow:add_hours(arrow:timestamp(), 8),

    StartLocal = {{Y, M, D}, {H1, 0, 0}},
    StartUTC = arrow:add_hours(arrow:timestamp(StartLocal), -8),

    EndLocal = {{Y, M, D}, {H2, 0, 0}},
    EndUTC = arrow:add_hours(arrow:timestamp(EndLocal), -8),

    {arrow:timestamp(StartUTC), arrow:timestamp(EndUTC)}.

