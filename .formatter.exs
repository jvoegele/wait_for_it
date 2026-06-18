# The WaitForIt macros read best without parentheses. These are listed under `locals_without_parens`
# for this project and re-exported so that consumers can pick them up via `import_deps: [:wait_for_it]`.
locals_without_parens = [
  wait: 1,
  wait: 2,
  wait!: 1,
  wait!: 2,
  match_wait: 2,
  match_wait: 3,
  match_wait!: 2,
  match_wait!: 3,
  case_wait: 2,
  case_wait: 3,
  case_wait!: 2,
  case_wait!: 3,
  cond_wait: 1,
  cond_wait: 2,
  cond_wait!: 1,
  cond_wait!: 2,
  with_wait: 2,
  with_wait: 3,
  with_wait!: 2,
  with_wait!: 3,
  signal: 1,
  assert_eventually: 1,
  assert_eventually: 2,
  refute_eventually: 1,
  refute_eventually: 2,
  assert_always: 1,
  assert_always: 2
]

[
  inputs: [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "mix.exs"
  ],
  line_length: 100,
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
