// Microseconds instead of milliseconds — 1000× finer granularity so rapid
// successive calls (e.g. setting multiple alarms in one message) never produce
// the same ID, and alarm IDs can't collide with reminder notification IDs.
int generateId() => DateTime.now().microsecondsSinceEpoch % 2147483647;
