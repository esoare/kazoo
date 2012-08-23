%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP INC
%%% @doc
%%% Handlers for various call events, acdc events, etc
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(acdc_agent_handler).

%% Listener callbacks
-export([handle_status_update/2
         ,handle_sync_req/2
         ,handle_sync_resp/2
         ,handle_call_event/2
         ,handle_member_message/2
        ]).

-include("acdc.hrl").

-spec handle_status_update/2 :: (wh_json:json_object(), wh_proplist()) -> 'ok'.
handle_status_update(JObj, _Props) ->
    true = wapi_acdc_agent:status_update_v(JObj),

    AcctId = wh_json:get_value(<<"Account-ID">>, JObj),
    AgentId = wh_json:get_value(<<"Agent-ID">>, JObj),
    Timeout = wh_json:get_integer_value(<<"Timeout">>, JObj),

    case wh_json:get_value(<<"New-Status">>, JObj) of
        <<"login">> -> maybe_start_agent(AcctId, AgentId);
        <<"logout">> -> maybe_stop_agent(AcctId, AgentId);
        <<"pause">> -> maybe_pause_agent(AcctId, AgentId, Timeout);
        <<"resume">> -> maybe_resume_agent(AcctId, AgentId)
    end.

maybe_start_agent(AcctId, AgentId) ->
    case acdc_agents_sup:find_agent_supervisor(AcctId, AgentId) of
        undefined ->
            lager:debug("agent ~s (~s) not found, starting", [AgentId, AcctId]),
            {ok, Agent} = couch_mgr:open_doc(wh_util:format_account_id(AcctId, encoded), AgentId),
            _R = acdc_agents_sup:new(AcctId, Agent),
            lager:debug("started agent at ~p", [_R]);
        P when is_pid(P) ->
            lager:debug("agent ~s (~s) already running: supervisor ~p", [AgentId, AcctId, P])
    end.

maybe_stop_agent(AcctId, AgentId) ->
    case acdc_agents_sup:find_agent_supervisor(AcctId, AgentId) of
        undefined -> lager:debug("agent ~s (~s) not found, nothing to do", [AgentId, AcctId]);
        P when is_pid(P) ->
            acdc_agent_sup:stop(P)
    end.

maybe_pause_agent(AcctId, AgentId, Timeout) ->
    case acdc_agents_sup:find_agent_supervisor(AcctId, AgentId) of
        undefined -> lager:debug("agent ~s (~s) not found, nothing to do", [AgentId, AcctId]);
        P when is_pid(P) ->
            FSM = acdc_agent_sup:fsm(P),
            acdc_agent_fsm:pause(FSM, Timeout)
    end.

maybe_resume_agent(AcctId, AgentId) ->
    case acdc_agents_sup:find_agent_supervisor(AcctId, AgentId) of
        undefined -> lager:debug("agent ~s (~s) not found, nothing to do", [AgentId, AcctId]);
        P when is_pid(P) ->
            FSM = acdc_agent_sup:fsm(P),
            acdc_agent_fsm:resume(FSM)
    end.

-spec handle_sync_req/2 :: (wh_json:json_object(), wh_proplist()) -> 'ok'.
handle_sync_req(JObj, Props) ->
    Defaults = wh_api:default_headers(props:get_value(queue, Props)
                                      ,?APP_NAME
                                      ,?APP_VERSION
                                     ),

    case props:get_value(status, Props) of
        init -> lager:debug("in init ourselves, ignoring sync request");
        ready -> sync_resp(JObj, ready, props:get_value(my_id, Props), Defaults);
        waiting -> sync_resp(JObj, waiting, props:get_value(my_id, Props), Defaults);
        ringing -> sync_resp(JObj, ringing, props:get_value(my_id, Props), Defaults);
        answered -> sync_resp(JObj, answered, props:get_value(my_id, Props)
                              ,[{<<"Call-ID">>, props:get_value(callid, Props)}
                                | Defaults
                               ]
                             );
        wrapup -> sync_resp(JObj, wrapup, props:get_value(my_id, Props)
                            ,[{<<"Time-Left">>, props:get_value(time_left, Props)}
                              | Defaults
                             ]
                           );
        paused -> sync_resp(JObj, paused, props:get_value(my_id, Props)
                            ,[{<<"Time-Left">>, props:get_value(time_left, Props)}
                              | Defaults
                             ]
                           )
    end.

-spec handle_sync_resp/2 :: (wh_json:json_object(), wh_proplist()) -> 'ok'.
handle_sync_resp(JObj, Props) ->
    acdc_agent_fsm:sync_resp(props:get_value(fsm_pid, Props), JObj).

-spec handle_call_event/2 :: (wh_json:json_object(), wh_proplist()) -> 'ok'.
handle_call_event(JObj, Props) ->
    {Cat, Name} = wh_util:get_event_type(JObj),
    lager:debug("call_event: ~s: ~s", [wh_json:get_value(<<"Call-ID">>, JObj), Name]),
    acdc_agent_fsm:call_event(props:get_value(fsm_pid, Props), Cat, Name, JObj).    

-spec handle_member_message/2 :: (wh_json:json_object(), wh_proplist()) -> 'ok'.
-spec handle_member_message/3 :: (wh_json:json_object(), wh_proplist(), ne_binary()) -> 'ok'.
handle_member_message(JObj, Props) ->
    handle_member_message(JObj, Props, wh_json:get_value(<<"Event-Name">>, JObj)).

handle_member_message(JObj, Props, <<"connect_req">>) ->
    acdc_agent_fsm:member_connect_req(props:get_value(fsm_pid, Props), JObj);
handle_member_message(JObj, Props, <<"connect_win">>) ->
    acdc_agent_fsm:member_connect_win(props:get_value(fsm_pid, Props), JObj);
handle_member_message(JObj, Props, <<"connect_monitor">>) ->
    acdc_agent_fsm:member_connect_monitor(props:get_value(fsm_pid, Props), JObj);
handle_member_message(_, _, EvtName) ->
    lager:debug("not handling member event ~s", [EvtName]).

-spec sync_resp/4 :: (wh_json:json_object(), acdc_agent:agent_status(), ne_binary(), wh_proplist()) -> 'ok'.
sync_resp(JObj, Status, MyId, Fields) ->
    Resp = props:filter_undefined(
             [{<<"Account-ID">>, wh_json:get_value(<<"Account-ID">>, JObj)}
              ,{<<"Agent-ID">>, wh_json:get_value(<<"Agent-ID">>, JObj)}
              ,{<<"Status">>, wh_util:to_binary(Status)}
              ,{<<"Process-ID">>, MyId}
              | Fields
             ]),
    wapi_agent:publish_sync_resp(wh_json:get_value(<<"Server-ID">>, JObj), Resp).
