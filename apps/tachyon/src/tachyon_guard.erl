%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2013, Lucera Financial Infrastructures
%%% @doc
%%%
%%% @end
%%% Created : 26 Jul 2013 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(tachyon_guard).

-behaviour(gen_server).
-include("packet_pb.hrl").
-include("tachyon_statistics.hrl").

%% API
-export([start_link/1, put/6, stop/1, stats/0, stats/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-define(DB_SERVER, "127.0.0.1").
-define(DB_PORT, 4242).

-record(state, {metrics = [], db, ip, time}).

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
start_link(IP) ->
    gen_server:start_link(
      {local, server_name(IP)},
      ?MODULE, [IP], []).

stop(IP) ->
    gen_server:cast(server_name(IP), stop).

put(IP, Host, Time, Metric, Value, T) ->
    gen_server:cast(server_name(IP), {put, Host, Time, Metric, Value, T}).

stats(IP) ->
    gen_server:call(server_name(IP), stats).

stats() ->
    case application:get_env(tachyon, clients) of
        {ok, IPs} ->
            [stats(IP) || IP <- IPs],
            ok;
        _ ->
            ok
    end.

server_name(IP) ->
    list_to_atom(IP ++ "_guard").
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
init([IP]) ->
    process_flag(trap_exit, true),
    {ok, DB} = gen_tcp:connect(?DB_SERVER, ?DB_PORT, [{packet, line}]),
    {ok, #state{db=DB, ip = IP}}.

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

handle_call(stats, _, State = #state{metrics = Metrics} ) ->
    io:format("===================="
              "===================="
              "===================="
              "===================="
              "===~n"
              "~45s~n"
              "===================="
              "===================="
              "===================="
              "===================="
              "===~n",
              [State#state.ip]),
    io:format("~20s ~20s ~20s ~s~n", ["Metric", "Average",
                                      "Standard Derivation", "Itterations"]),
    io:format("~20s ~20s ~20s ~s~n", ["--------------------",
                                 "--------------------",
                                 "--------------------",
                                 "--------------------"]),
    [io:format("~20s ~20.2f ~20.2f ~p~n", [N, M#running_avg.avg, M#running_avg.std, M#running_avg.itteration]) ||
        {N, M} <- Metrics],
    Dist = distance(State),
    {I, W, E} = lists:foldl(fun ({_, #running_avg{info = I0, warn = W0, error = E0}},
                                 {Ia, Wa, Ea}) ->
                                    {Ia + I0, Wa + W0, Ea + E0}
                            end, {0, 0, 0}, Metrics),
    io:format("Having a total of ~p infos, ~p warnings and ~p errors.~n",
              [I, W, E]),
    io:format("Total distance is ~.2f.~n", [Dist]),

    io:format("===================="
              "===================="
              "===================="
              "===================="
              "===~n"),
    {reply, ok, State};

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
handle_cast({put, Host, Time, Name, V, T}, State =
                #state{metrics = Metrics,
                       db = DB,
                       ip=IP,
                       time = T0}) ->
    Metrics1 =
        orddict:update(Name,
                       fun (Met) ->
                               M0 = tachyon_statistics:avg_update(Met, V),
                               {A, M} = tachyon_statistics:avg_analyze(M0, V, T),
                               case A of
                                   {error, Msg, Args} ->
                                       lager:error("[~s(~s)/~s] " ++ Msg,
                                                   [Host, IP, Name | Args]);
                                   {warn, Msg, Args} ->
                                       lager:warning("[~s(~s)/~s] " ++ Msg,
                                                   [Host, IP, Name | Args]);
                                   {info, Msg, Args} ->
                                       lager:info("[~s(~s)/~s] " ++ Msg,
                                                  [Host, IP, Name | Args]);
                                   _ ->
                                       ok
                               end,
                               M
                          end, #running_avg{avg=V}, Metrics),
    DB1 = DB,
    Metr = orddict:fetch(Name, Metrics1),
    State1  = State#state{metrics = Metrics1},
    Msg0 = case Time of
               T0 ->
                   [];
               _ ->
                   [io_lib:format("put cloud.diff ~p ~p host=~s~n",
                                  [T0, distance(State), Host])]
           end,
    TelnetMsg = [io_lib:format("put cloud.~s.avg ~p ~p host=~s~n",
                               [Name, Time, Metr#running_avg.avg, Host]),
                 io_lib:format("put cloud.~s.std ~p ~p host=~s~n",
                               [Name, Time, Metr#running_avg.std, Host]) | Msg0],
    DB1 = case gen_tcp:send(DB, TelnetMsg) of
              {error, Reason} ->
                  timer:sleep(1000),
                  io:format("[~s] Socket died with: ~p", [IP, Reason]),
                  {ok, NewDB} = gen_tcp:connect(?DB_SERVER, ?DB_PORT,
                                                [{packet, line}]),
                  NewDB;
              _ ->
                  DB
          end,
    {noreply, State1#state{db = DB1, time = Time}};

handle_cast(stop, State) ->
    {stop, normal, State};

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
terminate(_Reason, State) ->
    gen_tcp:close(State#state.db),
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
distance(#state{metrics = Metrics}) ->
    lists:foldl(fun({_, #running_avg{dist = Dist}}, Acc) ->
                        Acc + Dist
                end, 0.0, Metrics).