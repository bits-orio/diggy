# Diggy owns a diggy.* ODB catalog; milestone traffic stays MTS-owned

Diggy integrates with Open Discord Bridge directly (optional dependency), registering a `diggy.*` event catalog and emitting Diggy-specific events — collapses, deep-threat emergences, treasure finds — with MTS team labels when MTS is present. Milestone announcements are never emitted to ODB by Diggy when MTS is present: Diggy reports them via `mts-v1` `report_milestone` and MTS's existing ODB mirroring owns that traffic, avoiding double-posting. When MTS is absent, Diggy's own minimal milestone announcer posts to chat and ODB.

This mirrors how MTS itself integrates with ODB (catalog registration + suppression of overlapping baseline events).
