blocking:
- neat upgrade
- neat --version 0.1.7
- package.json "version", package-lock.json "version"
- dedicated bool type

pending:

- ranges
- fold ClassMethodPtr into LateSymbol
- endLifetime should not take or need to take a Reference!
- copyInto should not exist; instead there should be a copy() op that can then be chained into Assignment.
    - Sure? Needs more thinky. Maybe just `beginLifetime`?
