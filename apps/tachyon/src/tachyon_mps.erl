%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2014, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created : 27 Mar 2014 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(tachyon_mps).

-behaviour(gen_server).

%% API
-export([start_link/0, provide/0, handle/0, send/0]).
-ignore_xref([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(COUNTERS, tachyon_counters).
-record(state, {db}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

provide() ->
    ets:update_counter(?COUNTERS, provided, 1),
    ok.

handle() ->
    ets:update_counter(?COUNTERS, handled, 1),
    ok.

send() ->
    ets:update_counter(?COUNTERS, send, 1),
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
init([]) ->
    erlang:send_after(1000, self(), tick),
    ets:new(?COUNTERS, [named_table, set, public, {write_concurrency, true}]),
    ets:insert(?COUNTERS, {provided, 0}),
    ets:insert(?COUNTERS, {handled, 0}),
    ets:insert(?COUNTERS, {send, 0}),
    {ok, DB} = tachyon_kairos:connect(),
    {ok, Statsd} = tachyon_statsd:connect(),
    {ok, #state{db=[{tachyon_kairos, DB}, {tachyon_statsd, Statsd}]}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
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
handle_info(tick, State = #state{}) ->
    {MegaSecs, Secs, _} = now(),
    T = (MegaSecs*1000000 + Secs),
    [
     {handled, H},
     {provided, P},
     {send, S}
    ] = lists:sort(ets:tab2list(?COUNTERS)),
    ets:insert(?COUNTERS, {provided, 0}),
    ets:insert(?COUNTERS, {handled, 0}),
    ets:insert(?COUNTERS, {send, 0}),
    State1 = put(<<"tachyon.messages.handled">>, H, T, [], State),
    State2 = put(<<"tachyon.messages.provided">>, P, T, [], State1),
    State3 = put(<<"tachyon.messages.send">>, S, T, [], State2),
    erlang:send_after(1000, self(), tick),
    {noreply, State3};

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
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

put(Metric, Value, Time, Args, State = #state{db = DBs}) ->
    DBs1 = [{Mod, Mod:put(Metric, Value, Time, Args, DB)} ||
               {Mod, DB} <- DBs],
    State#state{db = DBs1}.
