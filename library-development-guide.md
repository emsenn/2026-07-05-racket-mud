## Engine State
Every *event* and *thing* has access to what is called the engine's "*scheduler/state pair." The name is pretty straight-forward: it's a sequence of:
- the procedure for scheduling a new *event* within the engine, to be called during the next *tick*.
- the current state of the MUD engine, including its extant things, scheduled events, hooks, and so on...

## Events
*Events* are functions which are scheduled by the engine and are called in the order they were scheduled each time the engine `ticks`. They accept a scheduler/state pair (passed automatically by the `tick`,) and return the same. This *(if properly implemented, would)* allows for the MUD's state to rolled-back to an earlier point within the same tick.

### Writing Events
As mentioned, *events* expect to be passed the engine's scheduler/state pair