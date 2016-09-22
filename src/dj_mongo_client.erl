%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Sep 2016 下午2:29
%%%-------------------------------------------------------------------
-module(dj_mongo_client).
-author("wang").

-behaviour(gen_server).
-behaviour(poolboy_worker).

%% API
-export([start_link/1,
    insert/2,
    delete/2,
    find/2,
    find_one/2,
    update/3]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {conn}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(term()) ->
    {ok, Pid :: pid()} | {error, Reason :: term()}).
start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).


insert(Collection, Doc) ->
    Worker = poolboy:checkout(pool1),
    Result = gen_server:call(Worker, {insert, Collection, Doc}),
    poolboy:checkin(pool1, Worker),
    Result.

delete(Collection, Selector) ->
    Worker = poolboy:checkout(pool1),
    Result = gen_server:call(Worker, {delete, Collection, Selector}),
    poolboy:checkin(pool1, Worker),
    Result.

find(Collection, Selector) ->
    Worker = poolboy:checkout(pool1),
    Result = gen_server:call(Worker, {find, Collection, Selector}),
    poolboy:checkin(pool1, Worker),
    Result.

find_one(Collection, Selector) ->
    Worker = poolboy:checkout(pool1),
    Result = gen_server:call(Worker, {find_one, Collection, Selector}),
    poolboy:checkin(pool1, Worker),
    Result.

update(Collection, Selector, Command) ->
    Worker = poolboy:checkout(pool1),
    Result = gen_server:call(Worker, {update, Collection, Selector, Command}),
    poolboy:checkin(pool1, Worker),
    Result.

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
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    io:format("DJ MONGO CLIENT INIT~n"),
    Opts = [{host, "127.0.0.1"}, {port, 27017}, {database, <<"dianjing1">>}],
    {ok, Conn} = mc_worker_api:connect(Opts),

    {ok, #state{conn = Conn}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call({insert, Collection, Doc}, _From, State) ->
    {{true, Result}, _} = mc_worker_api:insert(State#state.conn, Collection, Doc),

    Reply =
    case maps:find(<<"errmsg">>, Result) of
        {ok, ErrMsg} ->
            {error, ErrMsg};
        error ->
            ok
    end,

    {reply, Reply, State};

handle_call({delete, Collection, Selector}, _From, State) ->
    {true, _} = mc_worker_api:delete(State#state.conn, Collection, Selector),
    {reply, ok, State};

handle_call({find, Collection, Selector}, _From, State) ->
    Cursor = mc_worker_api:find(State#state.conn, Collection, Selector),
    Result = mc_cursor:rest(Cursor),
    {reply, {ok, Result}, State};

handle_call({find_one, Collection, Selector}, _From, State) ->
    Result = mc_worker_api:find_one(State#state.conn, Collection, Selector),
    {reply, {ok, Result}, State};

handle_call({update, Collection, Selector, Command}, _From, State) ->
    {true, _} = mc_worker_api:update(State#state.conn, Collection, Selector, Command),
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
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
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
    {noreply, State}.

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
    State :: #state{}) -> term()).
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
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
