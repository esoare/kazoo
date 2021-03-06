
%% -------------------------------------------------------------------
%%
%% nksip_call.hrl: SIP call processing types
%%
%% Copyright (c) 2013 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-ifndef(NKSIP_CALL_HRL_).
-define(NKSIP_CALL_HRL_, 1).


-define(DO_CALL_LOG(Level, Text, List), 
    ?DO_LOG(Level, erlang:get(nksip_app_name), erlang:get(nksip_call_id), Text, List)).


-define(call_debug(Text, List),
    case erlang:get(nksip_log_level)>=8 of
        true -> ?DO_CALL_LOG(debug, Text, List);
        false -> ok
    end).

-define(call_info(Text, List),
    case erlang:get(nksip_log_level)>=7 of
        true -> ?DO_CALL_LOG(info, Text, List);
        false -> ok
    end).

-define(call_notice(Text, List),
    case erlang:get(nksip_log_level)>=6 of
        true -> ?DO_CALL_LOG(notice, Text, List);
        false -> ok
    end).

-define(call_warning(Text, List),
    case erlang:get(nksip_log_level)>=5 of
        true -> ?DO_CALL_LOG(warning, Text, List);
        false -> 
            ok
    end).

-define(call_error(Text, List),
    case erlang:get(nksip_log_level)>=4 of
        true -> ?DO_CALL_LOG(error, Text, List);
        false -> ok
    end).



-type prack() :: {
    RSeq::nksip:cseq(), 
    CSeq::nksip:cseq(), 
    CSeqMethod:: nksip:method(),
    DialogId :: nksip_dialog:id()
}.


-record(trans, {
    id :: nksip_call_uac:id() | nksip_call_uas:id(),
    class :: uac | uas,
    status :: nksip_call_uac:status() | nksip_call_uas:status(),
    start :: nksip_lib:timestamp(),
    from :: none | {srv, from()} | {fork, nksip_call_fork:id()},
    opts :: nksip_lib:optslist(),
    trans_id :: integer(),
    request :: nksip:request(),
    method :: nksip:method(),
    ruri :: nksip:uri(),
    proto :: nksip:protocol(),
    response :: nksip:response(),
    code :: 0 | nksip:response_code(),
    to_tags = [] :: [nksip:tag()],
    stateless :: boolean(),
    rseq = 0 :: 0 | nksip:cseq(),
    pracks = [] :: [prack()],
    timeout_timer :: {nksip_call_lib:timeout_timer(), reference()},
    retrans_timer :: {nksip_call_lib:retrans_timer(), reference()},
    next_retrans :: non_neg_integer(),
    expire_timer :: {nksip_call_lib:expire_timer(), reference()},
    callback_timer :: {term(), reference()},
    cancel :: undefined | to_cancel | cancelled,
    loop_id :: integer(),
    ack_trans_id :: integer(),
    iter = 1 :: integer(),
    meta1 = [] :: nksip_lib:optslist()
}).


-record(fork, {
    id :: nksip_call_fork:id(),
    class :: uac | uas,
    start :: nksip_lib:timestamp(),
    request :: nksip:request(),
    method :: nksip:method(),
    opts :: nksip_lib:optslist(),
    uriset :: nksip:uri_set(),          
    uacs :: [integer()],
    pending :: [integer()],
    responses :: [nksip:response()], 
    final :: false | '2xx' | '6xx',
    meta = [] :: nksip_lib:optslist()   % No current use
}).


-record(provisional_event, {
    id :: {Id::nksip_subscription:id(), Tag::binary()},
    timer_n :: reference()
}).


-type call_auth() :: {
    nksip_dialog:id(), 
    nksip:protocol(), 
    inet:ip_address(), 
    inet:port_number()
}.


-type call_msg() :: {
    nksip_sipmsg:id(), 
    nksip_call_uac:id()|nksip_call_uas:id(), 
    nksip_dialog:id()
}.



%% Current Meta uses:
%% - nksip_min_se: Pre-dialog received MinSE header

-record(call, {
    app_id :: nksip:app_id(),
    call_id :: nksip:call_id(),
    hibernate :: atom(),
    next :: integer(),
    trans = [] :: [#trans{}],
    forks = [] :: [#fork{}],
    dialogs = [] :: [#dialog{}],
    auths = [] :: [call_auth()],
    msgs = [] :: [call_msg()],
    events = [] :: [#provisional_event{}],
    timers :: {T1::integer(), T2::integer(), T4::integer(), TC::integer(), App::integer()},
    meta = [] :: nksip_lib:optslist()
}).


-endif.
