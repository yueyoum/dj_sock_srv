%% -*- coding: utf-8 -*-
%% Automatically generated, do not edit
%% Generated by gpb_compile version 3.25.2

-ifndef(dj_protocol).
-define(dj_protocol, true).

-define(dj_protocol_gpb_version, "3.25.2").

-ifndef('PROTOPARTYINFO.PARTYMEMBER.BUYINFO_PB_H').
-define('PROTOPARTYINFO.PARTYMEMBER.BUYINFO_PB_H', true).
-record('ProtoPartyInfo.PartyMember.BuyInfo',
        {buy_id,                        % = 1, int32
         buy_times                      % = 2, int32
        }).
-endif.

-ifndef('PROTOPARTYINFO.PARTYMEMBER_PB_H').
-define('PROTOPARTYINFO.PARTYMEMBER_PB_H', true).
-record('ProtoPartyInfo.PartyMember',
        {id,                            % = 1, string
         flag,                          % = 2, int32
         name,                          % = 3, string
         seat_id,                       % = 4, int32
         buy_info = []                  % = 5, [{msg,'ProtoPartyInfo.PartyMember.BuyInfo'}]
        }).
-endif.

-ifndef('PROTOPARTYINFO_PB_H').
-define('PROTOPARTYINFO_PB_H', true).
-record('ProtoPartyInfo',
        {level,                         % = 1, int32
         end_at,                        % = 2, int64
         members = []                   % = 3, [{msg,'ProtoPartyInfo.PartyMember'}]
        }).
-endif.

-ifndef('PROTOPARTYMESSAGENOTIFY.PARTYMESSAGE_PB_H').
-define('PROTOPARTYMESSAGENOTIFY.PARTYMESSAGE_PB_H', true).
-record('ProtoPartyMessageNotify.PartyMessage',
        {tp,                            % = 1, {enum,'PartyMessageType'}
         args = []                      % = 2, [string]
        }).
-endif.

-ifndef('PROTOPARTYMESSAGENOTIFY_PB_H').
-define('PROTOPARTYMESSAGENOTIFY_PB_H', true).
-record('ProtoPartyMessageNotify',
        {session,                       % = 1, bytes
         act,                           % = 2, {enum,'Action'}
         messages = []                  % = 3, [{msg,'ProtoPartyMessageNotify.PartyMessage'}]
        }).
-endif.

-ifndef('PROTOPARTYCREATERESPONSE_PB_H').
-define('PROTOPARTYCREATERESPONSE_PB_H', true).
-record('ProtoPartyCreateResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYBUYREQUEST_PB_H').
-define('PROTOPARTYBUYREQUEST_PB_H', true).
-record('ProtoPartyBuyRequest',
        {session,                       % = 1, bytes
         buy_id                         % = 2, int32
        }).
-endif.

-ifndef('PROTOPARTYCHATREQUEST_PB_H').
-define('PROTOPARTYCHATREQUEST_PB_H', true).
-record('ProtoPartyChatRequest',
        {session,                       % = 1, bytes
         text                           % = 2, string
        }).
-endif.

-ifndef('PROTOPARTYQUITREQUEST_PB_H').
-define('PROTOPARTYQUITREQUEST_PB_H', true).
-record('ProtoPartyQuitRequest',
        {session                        % = 1, bytes
        }).
-endif.

-ifndef('PROTOPARTYROOMRESPONSE.PARTYROOM_PB_H').
-define('PROTOPARTYROOMRESPONSE.PARTYROOM_PB_H', true).
-record('ProtoPartyRoomResponse.PartyRoom',
        {owner_id,                      % = 1, string
         owner_name,                    % = 2, string
         level,                         % = 3, int32
         current_amount                 % = 4, int32
        }).
-endif.

-ifndef('PROTOSOCKETSERVERNOTIFY_PB_H').
-define('PROTOSOCKETSERVERNOTIFY_PB_H', true).
-record('ProtoSocketServerNotify',
        {session,                       % = 1, bytes
         ip,                            % = 2, string
         port                           % = 3, int32
        }).
-endif.

-ifndef('PROTOUTCNOTIFY_PB_H').
-define('PROTOUTCNOTIFY_PB_H', true).
-record('ProtoUTCNotify',
        {session,                       % = 1, bytes
         timestamp                      % = 2, int64
        }).
-endif.

-ifndef('PROTOPINGRESPONSE_PB_H').
-define('PROTOPINGRESPONSE_PB_H', true).
-record('ProtoPingResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOSYNCRESPONSE_PB_H').
-define('PROTOSYNCRESPONSE_PB_H', true).
-record('ProtoSyncResponse',
        {ret,                           % = 1, int32
         session,                       % = 2, bytes
         param                          % = 3, int32 (optional)
        }).
-endif.

-ifndef('PROTOPARTYDISMISSRESPONSE_PB_H').
-define('PROTOPARTYDISMISSRESPONSE_PB_H', true).
-record('ProtoPartyDismissResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYSTARTREQUEST_PB_H').
-define('PROTOPARTYSTARTREQUEST_PB_H', true).
-record('ProtoPartyStartRequest',
        {session                        % = 1, bytes
        }).
-endif.

-ifndef('PROTOPARTYKICKREQUEST_PB_H').
-define('PROTOPARTYKICKREQUEST_PB_H', true).
-record('ProtoPartyKickRequest',
        {session,                       % = 1, bytes
         id                             % = 2, string
        }).
-endif.

-ifndef('PROTOPARTYCREATEREQUEST_PB_H').
-define('PROTOPARTYCREATEREQUEST_PB_H', true).
-record('ProtoPartyCreateRequest',
        {session,                       % = 1, bytes
         id                             % = 2, int32
        }).
-endif.

-ifndef('PROTOSOCKETCONNECTREQUEST_PB_H').
-define('PROTOSOCKETCONNECTREQUEST_PB_H', true).
-record('ProtoSocketConnectRequest',
        {session                        % = 1, bytes
        }).
-endif.

-ifndef('PROTOPARTYINFONOTIFY_PB_H').
-define('PROTOPARTYINFONOTIFY_PB_H', true).
-record('ProtoPartyInfoNotify',
        {session,                       % = 1, bytes
         talent_id,                     % = 2, int32
         talent_end_at,                 % = 3, int64
         remained_create_times,         % = 4, int32
         remained_join_times,           % = 5, int32
         info                           % = 6, {msg,'ProtoPartyInfo'} (optional)
        }).
-endif.

-ifndef('PROTOSOCKETCONNECTRESPONSE_PB_H').
-define('PROTOSOCKETCONNECTRESPONSE_PB_H', true).
-record('ProtoSocketConnectResponse',
        {ret,                           % = 1, int32
         session,                       % = 2, bytes
         next_try_at                    % = 3, int64
        }).
-endif.

-ifndef('PROTOPARTYBUYRESPONSE_PB_H').
-define('PROTOPARTYBUYRESPONSE_PB_H', true).
-record('ProtoPartyBuyResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYDISMISSREQUEST_PB_H').
-define('PROTOPARTYDISMISSREQUEST_PB_H', true).
-record('ProtoPartyDismissRequest',
        {session                        % = 1, bytes
        }).
-endif.

-ifndef('PROTOPARTYJOINREQUEST_PB_H').
-define('PROTOPARTYJOINREQUEST_PB_H', true).
-record('ProtoPartyJoinRequest',
        {session,                       % = 1, bytes
         owner_id                       % = 2, string
        }).
-endif.

-ifndef('PROTOTIMERANGE_PB_H').
-define('PROTOTIMERANGE_PB_H', true).
-record('ProtoTimeRange',
        {start_at,                      % = 1, int64
         close_at                       % = 2, int64
        }).
-endif.

-ifndef('PROTOPARTYNOTIFY_PB_H').
-define('PROTOPARTYNOTIFY_PB_H', true).
-record('ProtoPartyNotify',
        {session,                       % = 1, bytes
         time_range = [],               % = 2, [{msg,'ProtoTimeRange'}]
         talent_id,                     % = 3, int32
         talent_end_at,                 % = 4, int64
         remained_create_times,         % = 5, int32
         remained_join_times            % = 6, int32
        }).
-endif.

-ifndef('PROTOPARTYCHATRESPONSE_PB_H').
-define('PROTOPARTYCHATRESPONSE_PB_H', true).
-record('ProtoPartyChatResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYKICKRESPONSE_PB_H').
-define('PROTOPARTYKICKRESPONSE_PB_H', true).
-record('ProtoPartyKickResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYQUITRESPONSE_PB_H').
-define('PROTOPARTYQUITRESPONSE_PB_H', true).
-record('ProtoPartyQuitResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYJOINRESPONSE_PB_H').
-define('PROTOPARTYJOINRESPONSE_PB_H', true).
-record('ProtoPartyJoinResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYROOMRESPONSE_PB_H').
-define('PROTOPARTYROOMRESPONSE_PB_H', true).
-record('ProtoPartyRoomResponse',
        {ret,                           % = 1, int32
         session,                       % = 2, bytes
         rooms = []                     % = 3, [{msg,'ProtoPartyRoomResponse.PartyRoom'}]
        }).
-endif.

-ifndef('PROTOPARTYSTARTRESPONSE_PB_H').
-define('PROTOPARTYSTARTRESPONSE_PB_H', true).
-record('ProtoPartyStartResponse',
        {ret,                           % = 1, int32
         session                        % = 2, bytes
        }).
-endif.

-ifndef('PROTOPARTYROOMREQUEST_PB_H').
-define('PROTOPARTYROOMREQUEST_PB_H', true).
-record('ProtoPartyRoomRequest',
        {session                        % = 1, bytes
        }).
-endif.

-ifndef('PROTOSYNCREQUEST_PB_H').
-define('PROTOSYNCREQUEST_PB_H', true).
-record('ProtoSyncRequest',
        {session,                       % = 1, bytes
         param                          % = 2, int32
        }).
-endif.

-ifndef('PROTOPINGREQUEST_PB_H').
-define('PROTOPINGREQUEST_PB_H', true).
-record('ProtoPingRequest',
        {session                        % = 1, bytes
        }).
-endif.

-endif.
