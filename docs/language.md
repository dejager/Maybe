# A small language, explained without a seminar

Maybe executes Probably 0.1 source. Keep the `.prob` file extension so the examples
remain recognizable across implementations. Filenames do not affect execution.

## Values and scope

```text
let message = input()
let attempts = 3
let ready = true
message = "New plan."
print(message)
```

Values are strings, nonnegative finite numbers, and booleans. Strings use double
quotes and JSON escapes: `\n`, `\t`, `\"`, `\\`, `\u263A`. Comments begin with `//`.
Semicolons are optional; newlines are whitespace. Names use ASCII letters, digits,
and underscores, beginning with a letter or underscore. Keywords cannot be names.

Each block owns its declarations. Inner blocks may shadow outer variables.
Assignment finds the nearest declaration. Declaring the same name twice in a block
or assigning an undeclared name is an error.

## Writing and judgment are different jobs

```text
let draft = llm "Make this clear and brief." using input()
print(draft)
```

`llm` returns a string. `using` passes one explicit value as context; other variables
stay in the interpreter. You can omit `using`. The legacy keyword `write` means the
same thing. Assign a generated result before using it in another generation; nested
`llm ... using llm ...` is rejected. `print` itself does not contact a model.

```text
if draft feels "clear enough for a new reader" with confidence 80% {
  print("Publish the draft.")
} otherwise maybe {
  print("Ask a new reader.")
} else {
  print("Try another rewrite.")
}
```

A judgment compares the description and its negation. The highest probability wins;
a tie picks yes. The threshold defaults to 50% and accepts 50–100%.

| Distribution at an 80% threshold | Branch |
| --- | --- |
| yes 90%, no 10% | first |
| yes 10%, no 90% | `else` |
| yes 60%, no 40% | `otherwise maybe` |

Both extra branches are optional. With no `otherwise maybe`, an uncertain judgment
runs neither the yes nor the no branch. The gate uses the winning choice probability,
not a separate provider confidence field. These numbers are estimates, not truth.

`feels` is only a condition inside `if` or `while`, not a standalone expression.

## Routing

```text
match input() {
  "a bug report" => { print("Investigate.") }
  "a feature request" => { print("Consider it.") }
  "something else" => { print("Read it yourself.") }
}
```

Use 2–8 distinct descriptions. The highest probability wins; ties pick the first.
`match` has no confidence gate in 0.1, so an “other” description is often useful.
There is no promise any label fits well.

## Loops with an exit strategy

```text
let draft = input()
while draft feels "full of corporate jargon" {
  draft = llm "Rewrite plainly." using draft
}
print(draft)

repeat 3 {
  print("No model was consulted for this repetition.")
}
```

`while` judges before every iteration and after the fifth rewrite. If it still
wants to continue, the run errors. It uses the default 50% gate. `repeat` accepts a
literal integer from 1–5. The whole run's effect and statement budgets still apply.

## Controlled irresponsibility

```text
chaos {
  if input() feels "urgent" {
    print("Treat it as urgent.")
  } else {
    print("Let it breathe.")
  }
}
```

Inside `chaos`, judgments sample their probabilities instead of always choosing the
largest. A 20% outcome has a 20% chance. Confidence is checked **before** sampling,
so a confident distribution may choose its minority answer. Chaos applies to
nested judgments, including `match` and `while`, not text generation temperature.
The random draw is recorded. Replay reproduces the decision.

## The boundaries are part of the language

| Limit | Default |
| --- | --- |
| Source | 12,000 UTF-16 code units |
| Input | 6,000 UTF-16 code units |
| Generated string | 12,000 UTF-16 code units |
| Block nesting | 12 |
| Executed statements | 200 |
| Model effects | 12 |
| Semantic loop iterations | 5 |
| Run deadline | 90 seconds, cooperative cancellation |
| Built-in HTTP request deadline | 25 seconds |

Errors stop the program. Events already emitted are retained by the caller; the
playground keeps them visible. A completed `Recording` is returned only on success.
No arithmetic, arrays, objects, functions, imports, arbitrary Swift/JavaScript, or
external tools exist in this version. A model's output remains a string.
