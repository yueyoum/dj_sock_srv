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
    party_create/1,
    party_start/1,
    party_buy/1,
    party_end/1]).

-export([api_response_handle/3,
    api_response_handle/4]).

-include("dj.hrl").

get(Path) ->
    {ok, Uri} = application:get_env(dj, http_server),
    request(get, Uri, Path, undefined).

post(Path, Body) when is_binary(Body) ->
    {ok, Uri} = application:get_env(dj, http_server),
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

    {ok, {_, _, ResponseBody}} = httpc:request(Method, Req, [], []),

    #{<<"code">> := Code, <<"data">> := Data,
        <<"extra">> := Extra, <<"others">> := Others} = json:from_binary(list_to_binary(ResponseBody)),
    if
        Code =:= 0 -> {ok, Data, Extra, Others};
        true -> {error, Code}
    end.

parse_session(Data) ->
    post("/api/session/parse/", Data).

party_create(Data) ->
    post("/api/party/create/", Data).

party_start(Data) ->
    post("/api/party/start/", Data).

party_buy(Data) ->
    post("/api/party/buy/", Data).

party_end(Data) ->
    post("/api/party/end/", Data).

%% ===================================
api_response_handle(Function, Arg, {M, F, A}) ->
    api_response_handle(Function, Arg, {M, F, A}, self()).

api_response_handle(Function, Arg, {M, F, A}, StreamTo) ->
    case dj_http_client:Function(Arg) of
        {ok, Data, Extra, Others} ->
            Return = M:F([Data | A]),
            % send extra response to StreamTo.
            % the extra response generated at http server
            case byte_size(Extra) > 0 of
                true -> api_response_stream(StreamTo, base64:decode(Extra));
                false -> ok
            end,

            api_response_handle_others(Others),
            Return;

        {error, ErrorCode} ->
            {error, atom_to_list(Function) ++ ", api error code: " ++ integer_to_list(ErrorCode), ErrorCode}
    end.

api_response_stream(undefined, _) ->
    ok;

api_response_stream(SteamTo, Extra) when is_pid(SteamTo)->
    case rpc:call(node(SteamTo), erlang, is_process_alive, [SteamTo]) of
        true ->
            SteamTo ! {api_return, Extra};
        false ->
            ok
    end.

api_response_handle_others([]) ->
    ok;

api_response_handle_others([Head | Tail]) ->
    #{<<"char_id">> := CharID, <<"data">> := Data, <<"extra">> := Extra} = Head,
    case gproc:where({n, g, dj_utils:char_id_to_binary_id(CharID)}) of
        undefined ->
            ok;
        Pid ->
            Pid ! {api_return, Data, Extra}
    end,
    api_response_handle_others(Tail).
