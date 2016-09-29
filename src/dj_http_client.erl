%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Sep 2016 上午5:42
%%%-------------------------------------------------------------------
-module(dj_http_client).
-author("wang").


%% API
-export([get/1,
    post/2,
    request/4,
    parse_session/1,
    party_create/3,
    party_start/4,
    party_buy/5,
    party_end/4]).

-include("dj_api.hrl").

get(Path) ->
    {ok, Uri} = application:get_env(dj_sock_srv, http_server),
    request(get, Uri, Path, undefined).

post(Path, Body) when is_binary(Body) ->
    {ok, Uri} = application:get_env(dj_sock_srv, http_server),
    request(post, Uri, Path, Body).

request(Method, Uri, Path, Body) ->
    Req =
    case Method of
        get ->
            {Uri ++ Path, []};
        _ ->
            Length = byte_size(Body),
            {Uri ++ Path, [{"content-length", integer_to_list(Length)}],
                "text/plain", Body
                }
    end,

    {ok, {{_, StatusCode, _}, _, ResponseBody}} = httpc:request(Method, Req, [], []),
    if
        StatusCode =:= 200 ->
            binary_to_term(list_to_binary(ResponseBody));
        true ->
            erlang:throw("bad api status code: " ++ integer_to_list(StatusCode))
    end.

%%    case StatusCode =:= 200 of
%%        true ->
%%            binary_to_term(list_to_binary(ResponseBody));
%%        flase ->
%%            erlang:throw("bad api status code: " ++ integer_to_list(StatusCode))
%%    end.


-spec parse_session(binary()) -> any().
parse_session(Session) ->
    Req = #'API.Session.Parse'{session = Session},
    post("/api/session/parse/", term_to_binary(Req)).

-spec party_create(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> any().
party_create(SID, CharID, PartyLevel) ->
    Req = #'API.Party.Create'{
        server_id = SID,
        char_id = CharID,
        party_level = PartyLevel
    },

    post("/api/party/create/", term_to_binary(Req)).

-spec party_start(non_neg_integer(), non_neg_integer(),
    non_neg_integer(), [non_neg_integer()]) -> any().
party_start(SID, CharID, PartyLevel, Members) ->
    Req = #'API.Party.Start'{
        server_id = SID,
        char_id = CharID,
        party_level = PartyLevel,
        members = Members
    },

    post("/api/party/start/", term_to_binary(Req)).

-spec party_buy(non_neg_integer(), non_neg_integer(),non_neg_integer(),
    non_neg_integer(), [non_neg_integer()]) -> any().
party_buy(SID, CharID, PartyLevel, BuyID, Members) ->
    Req = #'API.Party.Buy'{
        server_id = SID,
        char_id = CharID,
        party_level = PartyLevel,
        buy_id = BuyID,
        members = Members
    },

    post("/api/party/buy/", term_to_binary(Req)).

-spec party_end(non_neg_integer(), non_neg_integer(),
    non_neg_integer(), [non_neg_integer()]) -> any().
party_end(SID, CharID, PartyLevel, Members) ->
    Req = #'API.Party.End'{
        server_id = SID,
        char_id = CharID,
        party_level = PartyLevel,
        members = Members
    },

    post("/api/party/end/", term_to_binary(Req)).
