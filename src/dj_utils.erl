%%%-------------------------------------------------------------------
%%% @author wang
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Sep 2016 下午1:28
%%%-------------------------------------------------------------------
-module(dj_utils).
-author("wang").

%% API
-export([char_id_to_binary_id/1,
    char_id_to_party_room_key/1,
    binary_id_to_char_id/1,
    party_room_key_to_char_id/1]).

char_id_to_binary_id(ID) when is_integer(ID) ->
    char_id_to_binary_id(integer_to_binary(ID));

char_id_to_binary_id(ID) when is_binary(ID) ->
    << <<"char:">>/binary, ID/binary >>.

char_id_to_party_room_key(ID) when is_integer(ID) ->
    char_id_to_party_room_key(integer_to_binary(ID));

char_id_to_party_room_key(ID) when is_binary(ID) ->
    << <<"partychar:">>/binary, ID/binary >>.


binary_id_to_char_id(BinID) ->
    [_, ID] = binary:split(BinID, <<":">>),
    ID.

party_room_key_to_char_id(Key) ->
    [_, ID] = binary:split(Key, <<":">>),
    ID.