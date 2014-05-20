-module(tachyon_statsd).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([connect/0, put/5]).
-ignore_xref([connect/1, put/5]).
-record(statsd, {enabled}).

connect() ->
    case application:get_env(tachyon, statsd) of
        {ok, true} ->
            {ok, #statsd{enabled=true}};
        _ ->
            {ok, #statsd{enabled=false}}
    end.


put(Metric, Value, _Time, Args, #statsd{enabled=true}) ->
    Metrics = fmt(Metric, Args),
    estatsd:gauge(Metrics, Value),
    #statsd{enabled=true};

put(_Metric, _Value, _Time, _Args, #statsd{enabled=false}) ->
    #statsd{enabled=false}.

fmt(Metric, Args) ->
    list_to_binary([Metric | fmt_args(lists:reverse(Args), "")]).

fmt_args([{_, V}|R], Acc) when is_integer(V) ->
    fmt_args(R, [$., integer_to_list(V) | Acc]);
fmt_args([{_, V}|R], Acc) when is_float(V) ->
    fmt_args(R, [$., float_to_list(V) | Acc]);
fmt_args([{_, V}|R], Acc) when is_binary(V) orelse
                               is_list(V) ->
    fmt_args(R, [$., V | Acc]);

fmt_args([], Acc) ->
    Acc.

-ifdef(TEST).

fmt_test() ->
    Fmt = fmt(<<"a.metric">>, [{hypervisor, <<"bla">>}, {id, 1}]),
    ?assertEqual(<<"a.metric.bla.1">>, Fmt).

fmtno_arg_test() ->
    Fmt = fmt(<<"a.metric">>, []),
    ?assertEqual(<<"a.metric">>, Fmt).

-endif.
