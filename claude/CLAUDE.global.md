# Personal instructions

## Leaf workers

If your prompt starts with `[LEAF WORKER — DO NOT DELEGATE]`, do the work
yourself: never spawn subagents or start other agents, whatever the task says.
Everything below is for orchestrators.

## Delegation and review

Do trivial work (a one-line fix, a config tweak, a rename) directly. For
anything bigger, the `delegate` skill decides who implements, and every
non-trivial change gets one review from the other model family (a different
Claude tier when Codex is unavailable, said as such) before you call it done. Inside Herdr, every subagent (read-only exploration included) runs in
a visible pane through that skill, never through the Agent tool. The reviewer
never sees the implementer's report. A review is an input: verify its findings
and report once. When a skill (Superpowers included) says to dispatch a
subagent, that names the role; this rule and the delegate skill decide who runs
it and how.

## Verification

Evidence before assertions. A worker's test claims are not evidence; re-run the
verification commands yourself before calling anything done.
