%% Auto generate at 2016-09-29T18:05:27.407096.
%% By proto-ext
%% DO NOT EDIT



-record('API.Common.ExtraReturn', {
    char_id                       :: integer(),
    msgs                          :: [binary()]
}).

-record('API.Party.Create', {
    server_id                     :: integer(),
    char_id                       :: integer(),
    party_level                   :: integer()
}).

-record('API.Party.CreateDone', {
    ret                           :: integer(),
    extras                        :: [#'API.Common.ExtraReturn'{}]
}).

-record('API.Party.Start', {
    server_id                     :: integer(),
    char_id                       :: integer(),
    party_level                   :: integer(),
    members                       :: [integer()]
}).

-record('API.Party.StartDone', {
    ret                           :: integer(),
    extras                        :: [#'API.Common.ExtraReturn'{}]
}).

-record('API.Party.Buy', {
    server_id                     :: integer(),
    char_id                       :: integer(),
    party_level                   :: integer(),
    buy_id                        :: integer(),
    members                       :: [integer()]
}).

-record('API.Party.BuyDone', {
    ret                           :: integer(),
    extras                        :: [#'API.Common.ExtraReturn'{}],
    buy_name                      :: binary(),
    item_name                     :: binary(),
    item_amount                   :: integer()
}).

-record('API.Party.End', {
    server_id                     :: integer(),
    char_id                       :: integer(),
    party_level                   :: integer(),
    members                       :: [integer()]
}).

-record('API.Party.EndDone', {
    ret                           :: integer(),
    extras                        :: [#'API.Common.ExtraReturn'{}],
    talent_id                     :: integer()
}).

-record('API.Session.PartyInfo', {
    max_buy_times                 :: integer(),
    remained_create_times         :: integer(),
    remained_join_times           :: integer(),
    talent_id                     :: integer()
}).

-record('API.Session.Parse', {
    session                       :: binary()
}).

-record('API.Session.ParseDone', {
    ret                           :: integer(),
    extras                        :: [#'API.Common.ExtraReturn'{}],
    server_id                     :: integer(),
    char_id                       :: integer(),
    flag                          :: integer(),
    name                          :: binary(),
    partyinfo                     :: #'API.Session.PartyInfo'{}
}).
