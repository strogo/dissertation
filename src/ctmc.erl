-module(ctmc).

-export([start/2, interrupt/2]).
-export([behaviour_info/1]).

-behaviour(gen_server).
-export([code_change/3, handle_call/3, handle_cast/2, handle_info/2, init/1, terminate/2]).

-record(ctmc, {module, state, next_event}).
-define(SERVER, ?MODULE).

behaviour_info(callbacks) ->
    [{init,1},{events,1},{handle_event,2},{handle_interrupt,2}];

behaviour_info(_Other) ->
    undefined.

% api

start(Module, Args) ->
    gen_server:start(?MODULE, [Module, Args], []).

interrupt(Ctmc, Interrupt) ->
    gen_server:cast(Ctmc, {interrupt, Interrupt}).

% gen_server callbacks

init([Module, Args]) ->
    random:seed(now()),
    State = Module:init(Args),
    {Next_event, Timeout} = next_event(Module, State),
    {ok, #ctmc{module=Module, state=State, next_event=Next_event}, Timeout}.

handle_call(_Request, _From, _State) ->
    undefined.

handle_cast({interrupt, Interrupt}, #ctmc{module=Module, state=State}=Ctmc) ->
    State2 = Module:handle_interrupt(State, Interrupt),
    {Next_event, Timeout} = next_event(Module, State2),
    {noreply, Ctmc#ctmc{state=State2, next_event=Next_event}, Timeout}.

handle_info(timeout, #ctmc{module=Module, state=State, next_event=Next_event}=Ctmc) ->
    State2 = Module:handle_event(State, Next_event),
    {Next_event2, Timeout} = next_event(Module, State2),
    {noreply, Ctmc#ctmc{state=State2, next_event=Next_event2}, Timeout}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

% internal functions

next_event(Module, State) ->
    Events =  Module:events(State),
    Total = lists:sum([Rate || {_Event, Rate} <- Events]),
    case choose_event(Total * random:uniform(), Events) of
	no_event -> {no_event, infinity};
	{event, Event} -> {Event, round(1000 * exponential(Total))}
    end.

% rounding errors may occasionally cause spurious null events
% normally should only happen when the event list is empty
choose_event(_P, []) ->
    no_event;
choose_event(P, [{Event, Rate}|Events]) ->
    New_p = P - Rate,
    if 
	New_p =< 0 -> {event, Event};
	true -> choose_event(New_p, Events)
    end.

exponential(Lambda) ->
    P = random:uniform(),
    (-math:log(P) / Lambda).
