[
  inputs: [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "mix.exs"
  ],
  line_length: 100,
  locals_without_parens: [
    wait: 1,
    wait: 2,
    wait!: 1,
    wait!: 2,
    case_wait: 2,
    case_wait: 3,
    case_wait!: 2,
    case_wait!: 3,
    cond_wait: 1,
    cond_wait: 2,
    cond_wait!: 1,
    cond_wait!: 2,
    match_wait: 2,
    match_wait: 3,
    signal: 1
  ]
]
