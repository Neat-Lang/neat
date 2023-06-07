# Lambda Quarantine Checks

Reminder: there are (basically) three classes of lifetimes

- lexical: scope allocated, scope cleaned, `auto a = 5`, also covers parameters
- gifted: caller cleans, like `new Object`
- ephemeral: temporary scope, will be cleaned up by someone else some time
- permanent/none: globals.

To convert from lexical to gifted, we invoke `copy`. To construct a struct, we must convert to gifted,
thus we invoke `copy`.

Can lambdas be covered by these? No.

The logic for non-heap-allocated lambdas is driven by one case:

```
auto map(Range, Lambda)(Range range, Lambda lambda) {
    struct MapRange {
        ...
    }
    return MapRange(range, lambda);
}
```

This should not require allocations! But it constructs a struct, it returns a value.
Do we need full lifetime tracking after all?

Still no.

# Dynamic Quarantine

What we want is, given a lambda expression, `a => ...`, for it to be confined to a "dynamic quarantine":
that is, the stack space dynamically beneath the expression. We don't care about assignments,
constructions, parameter passing, so long as we cannot leave the quarantine area through them.

What is actually *unsafe*?

- Assignment to a class, array or hashmap field (any type that has its own refcounting)
- Return from the declaring function.

# Return checking

We introduce a method: `checkQuarantine` on `Type`. Right now, this only gates returning values.

We don't want to prevent returning from a function that's dynamically beneath the declaration. We only want
to prevent return from the function that the lambda actually captures. How do we disambiguate?

The lambda already knows which function declared it. So we can just check when returning from a function
if that function is the declaring function, and if so, error. This will work so long as
the quarantine is otherwise preserved.

# Quarantine policy

Assignment can be checked at the type level with `QuarantinePolicy`.

A container type indicates:

- transparent, if the value is guaranteed to recurse into the assigned field in `checkQuarantine`, for
  example structs.
- occluded, if the value may hide an assigned field on return, for example classes.

A value type indicates:

- checked, if we need to check quarantine on it, ie. lambdas
- harmless, if it uses the normal refcounting.

Then, we can just say that assigning a checked value to an occluded field is an error.

# Recursive functions

Q: But what about functions that pass a lambda to themselves recursively, and then return it from the
  recursive call?

A: Listen: I don't care about that usecase. This is intended to allow one thing: `map`, and functions like it.
  If you can think of a clever (and not excessively complicated) way to do it in this framework, patches
  welcome.
